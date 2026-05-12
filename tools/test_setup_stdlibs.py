"""Regression tests for tools/setup-stdlibs.py:ensure_clone().

Both bugs we hit during the ibc/ics23 stdlib removal -- the original
`go mod tidy` choke on a dangling stdlib import (because a prior run's
generated.go and symlink trees survived in the gno cache), and the
follow-up regression where the over-broad scrub also wiped the
native-binding deps that _inject_native_deps writes into the root
go.mod -- were misjudgments about which paths the scrub should touch.
Each scenario is encoded here so the next change in this area trips a
test instead of CI.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SETUP_SCRIPT = REPO_ROOT / "tools" / "setup-stdlibs.py"


def _git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def _commit_sha(repo: Path) -> str:
    out = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo, check=True, capture_output=True,
    )
    return out.stdout.decode().strip()


@pytest.fixture(scope="module")
def setup_stdlibs():
    """Load setup-stdlibs.py as a module despite the hyphen in its filename."""
    spec = importlib.util.spec_from_file_location("setup_stdlibs", SETUP_SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    # @dataclass resolves type annotations by looking up the owning module
    # via cls.__module__ in sys.modules; without this it raises on import.
    sys.modules["setup_stdlibs"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def upstream(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """A minimal git repo that mimics the upstream gno layout."""
    repo = tmp_path_factory.mktemp("upstream")
    _git(repo, "init", "--quiet", "--initial-branch=main")
    _git(repo, "config", "user.email", "test@example.com")
    _git(repo, "config", "user.name", "test")
    # Required for `git clone --filter=blob:none` against a local file:// URL.
    _git(repo, "config", "uploadpack.allowFilter", "true")
    (repo / "go.mod").write_text("module github.com/gnolang/gno\n\ngo 1.24.0\n")
    stdlibs = repo / "gnovm" / "stdlibs"
    stdlibs.mkdir(parents=True)
    (stdlibs / "generated.go").write_text(
        "// pristine upstream generated.go\npackage stdlibs\n"
    )
    _git(repo, "add", ".")
    _git(repo, "commit", "--quiet", "-m", "initial")
    return repo


@pytest.fixture
def warm_cache(setup_stdlibs, upstream, tmp_path):
    """A freshly-cloned cache + the version that produced it. Subsequent
    ensure_clone calls on the same cache exercise the warm-cache scrub path."""
    cache = tmp_path / "cache"
    version = setup_stdlibs.GnoVersion(
        repo=f"file://{upstream}", commit=_commit_sha(upstream)
    )
    setup_stdlibs.ensure_clone(version, cache)
    return cache, version


def test_warm_cache_scrubs_stale_stdlibs(setup_stdlibs, warm_cache):
    """Modified generated.go + leftover untracked stdlib dir get reset on the
    next ensure_clone call. Mirrors the ibc/ics23 cache-poisoning scenario."""
    cache, version = warm_cache
    gen = cache / "gnovm" / "stdlibs" / "generated.go"
    gen.write_text("// STALE FROM PRIOR RUN\npackage stdlibs\n")
    stale = cache / "gnovm" / "stdlibs" / "ibc" / "ics23"
    stale.mkdir(parents=True)
    (stale / "dangling.go").write_text("// dangling symlink target\n")

    setup_stdlibs.ensure_clone(version, cache)

    assert "STALE" not in gen.read_text()
    assert not stale.exists()


def test_warm_cache_preserves_root_go_mod(setup_stdlibs, warm_cache):
    """The scrub must leave the root go.mod alone, since _inject_native_deps
    writes the bn254/cometbls native-binding deps there and the CI cache-hit
    `make link-stdlibs` path does not re-inject them."""
    cache, version = warm_cache
    marker = "// injected by _inject_native_deps\n"
    go_mod = cache / "go.mod"
    go_mod.write_text(go_mod.read_text() + marker)

    setup_stdlibs.ensure_clone(version, cache)

    assert marker in go_mod.read_text()


def test_regenerate_tidies_gnodev_after_injecting_native_deps(setup_stdlibs, monkeypatch, tmp_path):
    """gnodev is its own Go module, so direct deps alone are not enough on a
    clean machine; its go.sum also needs transitive checksums from go mod tidy."""
    calls = []

    def fake_inject(module_dir: Path) -> None:
        calls.append(("inject", module_dir))

    def fake_run(cmd: list[str], cwd: Path | None = None) -> None:
        calls.append(("run", tuple(cmd), cwd))

    monkeypatch.setattr(setup_stdlibs, "_inject_native_deps", fake_inject)
    monkeypatch.setattr(setup_stdlibs, "run", fake_run)

    setup_stdlibs.regenerate_and_install(tmp_path, skip_install=False)

    gnodev = tmp_path / "contribs" / "gnodev"
    assert ("inject", gnodev) in calls
    assert ("run", ("go", "mod", "tidy"), gnodev) in calls
    assert calls.index(("inject", gnodev)) < calls.index(
        ("run", ("go", "mod", "tidy"), gnodev)
    )
    assert calls.index(("run", ("go", "mod", "tidy"), gnodev)) < calls.index(
        ("run", ("make", "install.gnodev"), tmp_path)
    )
