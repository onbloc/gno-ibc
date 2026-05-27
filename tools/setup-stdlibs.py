#!/usr/bin/env python3
"""Vendor gno-ibc native stdlibs into a pinned gno checkout, then build.

The pinned checkout comes from ``.gno-version``. Packages under ``stdlibs/``
are linked into ``<cache>/gnovm/stdlibs/<module>/`` so regenerated binaries
load the .gno sources and native Go bindings from this repo.
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

# Marks injected calibration rows and keeps reruns idempotent.
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
    """Clone or refresh the cached gno checkout at the pinned commit.

    Warm caches are cleaned only under ``gnovm/stdlibs/`` so generated files
    and stale symlinked packages do not leak across runs. If the pin moved, a
    full reset is needed before checkout because prior dependency injection can
    leave tracked ``go.mod`` files modified.
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
            # Prior dependency injection may block checkout after a pin move.
            run(["git", "reset", "--quiet", "--hard"], cwd=cache_dir)
            run(["git", "checkout", "--quiet", version.commit], cwd=cache_dir)
    else:
        run(["git", "checkout", "--quiet", version.commit], cwd=cache_dir)

    if not freshly_cloned:
        # Drop generated files and stale symlink dirs from prior runs.
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

    genstd uses ``os.Lstat`` and skips directory symlinks, so each package gets
    a real directory containing file-level symlinks.
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
    # The host module already provides gno deps.
    gno_module = "github.com/gnolang/gno"
    return [
        f"{mod}@{ver}"
        for mod, ver in sorted(requires.items())
        if not mod.startswith(gno_module)
        and ver != "v0.0.0-00010101000000-000000000000"
    ]


def _inject_native_deps(module_dir: Path) -> None:
    """Add extra stdlib native-binding deps to a Go module.

    Versions come from ``stdlibs/go.mod`` so local tooling and this script stay
    in sync.
    """
    deps = _native_deps()
    if not deps:
        return
    log(f"injecting native stdlib deps into {module_dir}: {deps}")
    run(["go", "get"] + deps, cwd=module_dir)


def _load_calibration_rows(path: Path) -> list[str]:
    """Read the calibration data file and return only entry-row lines.

    Comment-only and blank lines are ignored; remaining lines are inserted as
    ``nativeGasEntry`` rows.
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

    Older pins without ``native_gas.go``, empty data files, and reruns after
    sentinel insertion are treated as no-ops.
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
    # Keep VERSION and GNOROOT_DIR ldflags aligned with upstream.
    run(["make", "install"], cwd=gnovm)
    # gnoland and gnodev share the regenerated stdlib dispatch table.
    run(["make", "install.gnoland"], cwd=gnoland)
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
    # Let CI override the pin without editing .gno-version.
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
