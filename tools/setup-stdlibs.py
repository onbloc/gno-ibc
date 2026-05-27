#!/usr/bin/env python3
"""Vendor gno-ibc's native stdlibs into a pinned gno checkout, then build.

Reads ``.gno-version`` for the upstream gno repo + commit, ensures a checkout
under ``~/.cache/gno-ibc/gno``, symlinks every package under ``stdlibs/`` into
``<cache>/gnovm/stdlibs/<module>/``, regenerates the native-binding dispatch
table, and installs the resulting ``gno``, ``gnodev``, and ``gnokey`` binaries.

The symlinks are the load-bearing part: the gno binary's baked-in ``_GNOROOT``
points at the cache, so at runtime it walks the symlinked dirs to load .gno
sources, while the regenerated ``generated.go`` (compiled into the binary)
wires ``X_<func>`` Go bindings into the dispatch table.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

try:
    import tomllib  # Python 3.11+
except ImportError:
    try:
        import tomli as tomllib  # type: ignore[import-not-found, no-redef]
    except ImportError:
        raise SystemExit("ERROR: need Python 3.11+ or `pip install tomli`.")


REPO_ROOT = Path(__file__).resolve().parent.parent
GNO_VERSION_FILE = REPO_ROOT / ".gno-version"
STDLIBS_DIR = REPO_ROOT / "stdlibs"
NATIVE_GAS_CALIBRATION_FILE = STDLIBS_DIR / "native_gas_calibration.txt"
DEFAULT_CACHE = Path.home() / ".cache" / "gno-ibc" / "gno"

# Sentinel comment marking gno-ibc-injected calibration rows so that
# inject_calibrated_natives can detect a prior injection and stay idempotent.
# The ensure_clone scrub (`git checkout HEAD -- gnovm/stdlibs`) drops the
# sentinel together with the rows, so each fresh-pin run reapplies cleanly.
_CALIBRATION_SENTINEL = "// gno-ibc:calibrated-natives"
_CALIBRATION_SLICE_OPEN = "var calibratedNativeGas = []nativeGasEntry{"


@dataclass(frozen=True)
class GnoVersion:
    repo: str
    commit: str


@dataclass(frozen=True)
class Stdlib:
    source_dir: Path  # absolute path under stdlibs/
    module_path: str  # e.g. "crypto/bn254"

    def link_target(self, cache_dir: Path) -> Path:
        return cache_dir / "gnovm" / "stdlibs" / self.module_path


def log(msg: str) -> None:
    print(f"[setup-stdlibs] {msg}", flush=True)


def parse_gno_version(path: Path) -> GnoVersion:
    """Parse the Makefile-include style .gno-version (KEY=VALUE per line)."""
    repo = commit = None
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if key == "GNO_REPO":
            repo = value
        elif key == "GNO_COMMIT":
            commit = value
    if not repo or not commit:
        raise SystemExit(f"ERROR: {path} is missing GNO_REPO or GNO_COMMIT")
    return GnoVersion(repo=repo, commit=commit)


def run(cmd: list[str], cwd: Path | None = None) -> None:
    """Run a command, streaming output; raise on non-zero exit."""
    pretty = " ".join(cmd) + (f"  (cwd={cwd})" if cwd else "")
    log(f"$ {pretty}")
    subprocess.run(cmd, cwd=cwd, check=True)


def ensure_clone(version: GnoVersion, cache_dir: Path) -> None:
    """Clone the gno repo into cache_dir if needed; fetch + checkout the pin.

    Uses ``--filter=blob:none`` (partial clone) so the initial network fetch
    skips file blobs; ``git checkout`` then lazily downloads only the blobs
    reachable from the pinned commit. Materially faster than a full clone on
    cold CI runs while still supporting arbitrary commit checkouts.

    On warm caches, scrubs leftover state from a prior run under
    ``gnovm/stdlibs/`` — the regenerated ``generated.go`` plus untracked
    symlink directories for stdlibs that have since been removed from this
    repo. Without this, CI's ``restore-keys`` cache fallback resurrects
    those stale paths on a key miss and ``go mod tidy`` chokes on the
    dangling stdlib imports inside ``generated.go``.

    The scrub is normally scoped to ``gnovm/stdlibs/``: the root
    ``go.mod`` / ``go.sum`` carry the native-binding deps that
    ``_inject_native_deps`` adds, and the ``make link-stdlibs`` cache-hit
    path on CI does not re-inject them. Resetting the whole tree would
    strip those deps and break ``go test`` against the native bindings.

    Exception: when the pin moves (warm cache with prior `_inject_native_deps`
    modifications, but a new ``version.commit``), ``git checkout`` fails on
    the tracked root ``go.mod`` modifications. In that case we hard-reset
    before the checkout. ``regenerate_and_install`` reapplies the deps right
    after. Link-only callers (`--link-only`) who change the pin lose those
    deps, but that combination has no valid use case (a pin bump requires
    a full rebuild).
    """
    freshly_cloned = not (cache_dir / ".git").is_dir()
    if freshly_cloned:
        cache_dir.parent.mkdir(parents=True, exist_ok=True)
        run([
            "git", "clone", "--quiet",
            "--filter=blob:none",
            version.repo, str(cache_dir),
        ])
    have_commit = subprocess.run(
        ["git", "cat-file", "-e", f"{version.commit}^{{commit}}"],
        cwd=cache_dir,
        capture_output=True,
    ).returncode == 0
    if not have_commit:
        run(["git", "fetch", "--quiet", "origin"], cwd=cache_dir)

    if not freshly_cloned:
        head_sha = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=cache_dir, capture_output=True, check=True,
        ).stdout.decode().strip()
        if head_sha != version.commit:
            # Pin moved. Tracked root go.mod / contribs/gnodev/go.mod
            # modifications from a prior `_inject_native_deps` block
            # `git checkout`. Hard-reset to clear them. The deps get
            # re-added by `regenerate_and_install` below.
            run(["git", "reset", "--quiet", "--hard"], cwd=cache_dir)
            run(["git", "checkout", "--quiet", version.commit], cwd=cache_dir)
    else:
        run(["git", "checkout", "--quiet", version.commit], cwd=cache_dir)

    if not freshly_cloned:
        # Drop tracked modifications inside gnovm/stdlibs (notably
        # generated.go after a prior `go generate`) then prune untracked
        # symlink dirs from packages that no longer exist in this repo.
        # `link_stdlib` recreates the ones still present right after this
        # returns.
        run(["git", "checkout", "--quiet", "HEAD", "--",
             "gnovm/stdlibs"], cwd=cache_dir)
        run(["git", "clean", "-fd", "--quiet", "--",
             "gnovm/stdlibs"], cwd=cache_dir)


def discover_stdlibs(root: Path) -> Iterator[Stdlib]:
    """Yield every directory under root that contains a gnomod.toml."""
    for toml_path in sorted(root.rglob("gnomod.toml")):
        with toml_path.open("rb") as fh:
            data = tomllib.load(fh)
        module_path = data.get("module")
        if not module_path:
            log(f"WARN: {toml_path} has no `module` key, skipping")
            continue
        yield Stdlib(source_dir=toml_path.parent, module_path=module_path)


def link_stdlib(stdlib: Stdlib, cache_dir: Path) -> None:
    """Mirror source_dir into target as a real dir + per-file symlinks.

    A directory-level symlink would be simpler, but genstd's WalkDir uses
    os.Lstat, which does not follow symlinked directories — the package would
    be silently skipped during native-binding generation. A real directory
    with file-level symlinks lets WalkDir descend, and parser.ParseFile then
    resolves each symlink to the source file under stdlibs/.
    """
    target = stdlib.link_target(cache_dir)
    source = stdlib.source_dir.resolve()

    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.is_dir():
        shutil.rmtree(target)

    target.mkdir(parents=True)
    for src_file in sorted(source.rglob("*")):
        if not src_file.is_file():
            continue
        rel = src_file.relative_to(source)
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.symlink_to(src_file)
    log(f"  link  {stdlib.module_path}  ->  {source}")


def _read_direct_requires(gomod_path: Path) -> dict[str, str]:
    """Parse direct (non-indirect) require entries from a go.mod file."""
    requires: dict[str, str] = {}
    if not gomod_path.is_file():
        return requires
    in_block = False
    for raw in gomod_path.read_text().splitlines():
        line = raw.strip()
        if line == "require (":
            in_block = True
            continue
        if in_block and line == ")":
            in_block = False
            continue
        if line.startswith("require ") and "(" not in line:
            parts = line[len("require "):].split()
            if len(parts) >= 2 and "// indirect" not in line:
                requires[parts[0]] = parts[1]
            continue
        if in_block and line and not line.startswith("//") and "// indirect" not in line:
            parts = line.split()
            if len(parts) >= 2:
                requires[parts[0]] = parts[1]
    return requires


def _native_deps() -> list[str]:
    """Return extra Go deps declared by this repo's native stdlibs."""
    requires = _read_direct_requires(REPO_ROOT / "stdlibs" / "go.mod")
    # Deps that start with the gno module prefix are already provided by the
    # host module; skip them and the replace-directive placeholder version.
    gno_module = "github.com/gnolang/gno"
    return [
        f"{mod}@{ver}"
        for mod, ver in sorted(requires.items())
        if not mod.startswith(gno_module)
        and ver != "v0.0.0-00010101000000-000000000000"
    ]


def _inject_native_deps(module_dir: Path) -> None:
    """Add extra stdlib native-binding deps to a Go module.

    Native stdlib .go files may import third-party packages that are not yet
    in the upstream gno go.mod. Reading the versions from stdlibs/go.mod keeps
    this script and the IDE-support go.mod in sync automatically.
    """
    deps = _native_deps()
    if not deps:
        return
    log(f"injecting native stdlib deps into {module_dir}: {deps}")
    run(["go", "get"] + deps, cwd=module_dir)


def _load_calibration_rows(path: Path) -> list[str]:
    """Read the calibration data file and return only entry-row lines.

    Strips comment-only and blank lines so the data file can carry header
    docs alongside the rows. Each surviving line is expected to be a single
    nativeGasEntry struct literal terminated with a comma (matching the
    format upstream produces from gen_native_table.py).
    """
    if not path.is_file():
        return []
    rows: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.rstrip()
        stripped = line.lstrip()
        if not stripped or stripped.startswith("//"):
            continue
        rows.append(line)
    return rows


def _inject_calibrated_natives(cache_dir: Path) -> None:
    """Append gno-ibc calibration rows into upstream's calibratedNativeGas.

    No-op when:
      * gnovm/stdlibs/native_gas.go does not exist (pre-#5629 pin)
      * the sentinel comment is already present (idempotent rerun)
      * the calibration data file is empty or missing

    Inserts the rows right before the slice's closing brace, preceded by the
    sentinel comment. ensure_clone's scrub
    (``git checkout HEAD -- gnovm/stdlibs``) removes both the sentinel and
    the rows, so every fresh-pin invocation reapplies from scratch.
    """
    target = cache_dir / "gnovm" / "stdlibs" / "native_gas.go"
    if not target.is_file():
        log(f"  skip calibration injection: {target.relative_to(cache_dir)} not in pin")
        return
    rows = _load_calibration_rows(NATIVE_GAS_CALIBRATION_FILE)
    if not rows:
        log(f"  skip calibration injection: {NATIVE_GAS_CALIBRATION_FILE.name} has no rows")
        return

    src = target.read_text()
    if _CALIBRATION_SENTINEL in src:
        log("  calibration injection: sentinel already present, skipping")
        return

    lines = src.splitlines(keepends=True)
    open_idx = next(
        (i for i, line in enumerate(lines) if line.strip() == _CALIBRATION_SLICE_OPEN),
        -1,
    )
    if open_idx < 0:
        raise SystemExit(
            f"ERROR: {target} does not contain '{_CALIBRATION_SLICE_OPEN}' "
            f"(upstream changed the slice declaration?)"
        )
    close_idx = next(
        (i for i in range(open_idx + 1, len(lines)) if lines[i].rstrip() == "}"),
        -1,
    )
    if close_idx < 0:
        raise SystemExit(
            f"ERROR: {target} has no closing brace after "
            f"'{_CALIBRATION_SLICE_OPEN}'"
        )

    block = [f"\t{_CALIBRATION_SENTINEL}\n"]
    for row in rows:
        block.append("\t" + row.lstrip() + "\n")

    new_lines = lines[:close_idx] + block + lines[close_idx:]
    target.write_text("".join(new_lines))
    log(f"  calibration injection: appended {len(rows)} row(s) to {target.relative_to(cache_dir)}")


def regenerate_and_install(cache_dir: Path, skip_install: bool) -> None:
    gnovm = cache_dir / "gnovm"
    gnodev = cache_dir / "contribs" / "gnodev"
    gnoland = cache_dir / "gno.land"
    _inject_native_deps(cache_dir)
    _inject_calibrated_natives(cache_dir)
    run(["go", "mod", "tidy"], cwd=gnovm)
    run(["go", "generate", "./stdlibs/..."], cwd=gnovm)
    if skip_install:
        log("skipping `make install` (per --skip-install)")
        return
    # Delegate to gnovm/Makefile so VERSION + GNOROOT_DIR ldflags match the
    # upstream install path.
    run(["make", "install"], cwd=gnovm)
    # gnoland shares the same stdlib dispatch table; rebuild it so native
    # bindings added by this repo's stdlibs/ are included in the binary.
    run(["make", "install.gnoland"], cwd=gnoland)
    # gnodev embeds the same stdlib dispatch table through gnovm, so rebuild it
    # from the same checkout after stdlib generation. Otherwise an older
    # gnodev binary can keep looking for stdlibs removed from this repo.
    _inject_native_deps(gnodev)
    run(["go", "mod", "tidy"], cwd=gnodev)
    run(["make", "install.gnodev"], cwd=cache_dir)
    run(["make", "install.gnokey"], cwd=cache_dir)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    p.add_argument(
        "--cache-dir",
        type=Path,
        default=DEFAULT_CACHE,
        help=f"Where to clone gno (default: {DEFAULT_CACHE})",
    )
    p.add_argument(
        "--skip-install",
        action="store_true",
        help="Stop after `go generate`; don't install the binary",
    )
    p.add_argument(
        "--link-only",
        action="store_true",
        help="Only ensure the clone + refresh stdlib symlinks; skip generate + install",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if not GNO_VERSION_FILE.is_file():
        raise SystemExit(f"ERROR: {GNO_VERSION_FILE} not found")
    if not STDLIBS_DIR.is_dir():
        raise SystemExit(f"ERROR: {STDLIBS_DIR} not found")

    version = parse_gno_version(GNO_VERSION_FILE)
    # Allow GNO_COMMIT / GNO_REPO env vars (exported by the Makefile) to
    # override the file pin without touching .gno-version. Used by the
    # coverage workflow to install gnolang/gno#4241 alongside the regular
    # toolchain.
    env_repo = os.environ.get("GNO_REPO")
    env_commit = os.environ.get("GNO_COMMIT")
    if (env_repo and env_repo != version.repo) or (env_commit and env_commit != version.commit):
        version = GnoVersion(
            repo=env_repo or version.repo,
            commit=env_commit or version.commit,
        )
        log(f"override from env: repo={version.repo} commit={version.commit[:12]}")
    log(f"gno = {version.repo} @ {version.commit[:12]}")
    log(f"cache = {args.cache_dir}")

    ensure_clone(version, args.cache_dir)

    stdlibs = list(discover_stdlibs(STDLIBS_DIR))
    if not stdlibs:
        raise SystemExit(f"ERROR: no gnomod.toml found under {STDLIBS_DIR}")
    log(f"vendoring {len(stdlibs)} stdlib package(s):")
    for sl in stdlibs:
        link_stdlib(sl, args.cache_dir)

    if args.link_only:
        log("done (link-only: skipped generate + install).")
        return 0

    regenerate_and_install(args.cache_dir, skip_install=args.skip_install)

    log("done.")
    if not args.skip_install:
        gobin = subprocess.check_output(["go", "env", "GOPATH"]).decode().strip()
        log(f"installed: {gobin}/bin/gno")
        log(f"installed: {gobin}/bin/gnoland")
        log(f"installed: {gobin}/bin/gnodev")
        log(f"installed: {gobin}/bin/gnokey")
    return 0


if __name__ == "__main__":
    sys.exit(main())
