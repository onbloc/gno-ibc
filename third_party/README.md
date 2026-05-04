---
name: third_party
description: Sparse-checkout submodules of upstream gno repos that supply non-stdlib packages this workspace depends on.
---

# Third-party submodules

This directory holds **sparse-checkout submodules** of upstream gno repositories. Each submodule's pinned commit is the source of truth for one or more packages mirrored into `gno.land/p/<org>/<pkg>/`. The mirrored copies are `.gitignore`d — only the submodule pin is committed.

## Why submodules + mirror, not just submodules?

The gno toolchain discovers workspace packages by their on-disk path: `gno.land/p/onbloc/json` must contain `node.gno` directly, not nested several directories deep. But the upstream packages live at sub-paths inside their parent repos (`examples/gno.land/p/onbloc/json/` in `gnolang/gno`, `contract/p/gnoswap/uint256/` in `gnoswap-labs/gnoswap`), so a plain `git submodule add` at the workspace path would mount the entire upstream repo at the wrong place.

The toolchain also does not follow filesystem symlinks for workspace discovery, so symlinking from the workspace path into the submodule's sub-path does not work.

The compromise: submodule mounts the upstream repo at `third_party/<name>/`, sparse-checkout narrows the working tree to the relevant sub-path, and `make vendor` rsyncs that sub-path into the workspace location. The workspace path is `.gitignore`d.

## Active mirrors

| Workspace path                  | Source submodule                    | Sub-path                                    | Used by |
| ------------------------------- | ----------------------------------- | ------------------------------------------- | ------- |
| `gno.land/p/onbloc/json/`       | `third_party/gnolang-gno`           | `examples/gno.land/p/onbloc/json/`          | ZKGM port |
| `gno.land/p/gnoswap/uint256/`   | `third_party/gnoswap`               | `contract/p/gnoswap/uint256/`               | ZKGM port, CometBLS light client, `p/core/_smoke/` |

## Workflow

```bash
make vendor          # idempotent: init/update submodules, sync sparse-checkout, rsync mirrors
```

`make test` and `make test-smoke` depend on `vendor`, so a fresh clone followed by `make test` populates the mirrors automatically.

## Bumping a pin

```bash
# fetch new upstream commits
git -C third_party/<name> fetch origin
git -C third_party/<name> checkout <new-commit>
# record the new pin in this repo
git add third_party/<name>
git commit -m "vendor: bump <name> to <new-commit>"
make vendor          # refresh the mirror
```

## Graduation

If a vendored package becomes resolvable via gno's own package registry / chain pull (or moves into stdlibs), drop the submodule + the corresponding `.gitignore` line + the `VENDOR_*` block in the Makefile, and rely on regular import resolution.
