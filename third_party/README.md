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

The Makefile (`VENDOR_*` blocks) is the source of truth — keep this table in sync when packages are added or dropped.

### `third_party/gnolang-gno` → `examples/gno.land/<rel>/`

| Workspace path                       | Used by |
| ------------------------------------ | ------- |
| `gno.land/p/demo/tokens/grc20/`      | ZKGM voucher tokens |
| `gno.land/p/moul/md/`                | gno-realms transitive |
| `gno.land/p/onbloc/diff/`            | gno-realms transitive |
| `gno.land/p/onbloc/json/`            | ZKGM port |
| `gno.land/p/nt/avl/v0/`              | ZKGM, IBC core (key-value storage) |
| `gno.land/p/nt/bptree/v0/`           | gno-realms transitive |
| `gno.land/p/nt/cford32/v0/`          | gno-realms transitive |
| `gno.land/p/nt/fqname/v0/`           | gno-realms transitive |
| `gno.land/p/nt/mux/v0/`              | gno-realms transitive |
| `gno.land/p/nt/seqid/v0/`            | ZKGM, IBC core (monotonic IDs) |
| `gno.land/p/nt/testutils/v0/`        | tests |
| `gno.land/p/nt/uassert/v0/`          | tests |
| `gno.land/p/nt/ufmt/v0/`             | string formatting |
| `gno.land/r/demo/defi/grc20reg/`     | global GRC20 registry for ZKGM vouchers |

### `third_party/gnoswap` → `contract/<rel>/`

| Workspace path                  | Used by |
| ------------------------------- | ------- |
| `gno.land/p/gnoswap/uint256/`   | ZKGM port, CometBLS light client, `p/core/_smoke/` |

### `third_party/gno-realms` → `gno.land/<rel>/`

| Workspace path                                            | Used by |
| --------------------------------------------------------- | ------- |
| `gno.land/p/aib/encoding/`                                | IBC encoding helpers |
| `gno.land/p/aib/ics23/`                                   | ICS-23 commitment proofs |
| `gno.land/p/aib/jsonpage/`                                | gno-realms transitive |
| `gno.land/p/aib/merkle/`                                  | merkle helpers |
| `gno.land/p/aib/ibc/app/`                                 | IBC app interface |
| `gno.land/p/aib/ibc/host/`                                | IBC host interface |
| `gno.land/p/aib/ibc/lightclient/`                         | light-client interface |
| `gno.land/p/aib/ibc/lightclient/tendermint/`              | tendermint light client |
| `gno.land/p/aib/ibc/lightclient/tendermint/testing/`      | tests |
| `gno.land/p/aib/ibc/types/`                               | IBC type definitions |
| `gno.land/r/aib/ibc/core/`                                | IBC core realm (channels, clients, packets) — consumed by ZKGM filetests as `core` |

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
