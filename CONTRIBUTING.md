# Contributing

This repository is for Gno-side IBC Union implementation work. Keep changes
scoped to the package, realm, tool, or document you are updating.

## Prerequisites

- Go, for building the pinned Gno toolchain and native bindings.
- Git submodule support, used by `make vendor`.
- `nix develop` is optional but recommended; it provides the supporting
  toolchain used by this workspace.
- Rust and Cargo are required only when refreshing ABI or ZKGM fixture vectors.

The Gno binaries themselves are not supplied by the flake. Build them with
`make install-gno` so `gno`, `gnodev`, and `gnokey` match the commit pinned in
`.gno-version`. The IBC crypto stdlibs ship in that upstream pin, so this repo
no longer vendors them locally.

## Quick Start

```bash
nix develop          # optional: enter the pinned development shell
make install-gno     # build and install gno, gnodev, and gnokey
make test            # vendor dependencies and run first-party Gno tests
```

If `make test` reports that `gno` is missing or points at the wrong commit,
ensure `$(go env GOPATH)/bin` is on `PATH`, then rerun `make install-gno`.

## Common Tasks

```bash
make vendor                    # mirror sparse third-party packages into gno.land/
make test                      # run first-party Gno package and realm tests
make test-gnokey-query-smoke   # run the full gnokey smoke suite
make refresh-zkgm-scenarios    # regenerate ZKGM handler scenario fixtures
make generate-check            # verify generated protobuf codecs are current
```

Focused Gno test runs are useful during development:

```bash
gno test -v ./gno.land/r/onbloc/ibc/union/core
gno test -v ./gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1
gno test -v ./gno.land/p/onbloc/ibc/union/zkgm
```

## Gno Development Notes

- `.gno` files are Gno, not Go. Use `gnomod.toml` module manifests and
  `gno.land/p/...` or `gno.land/r/...` import paths.
- Stateful contracts live under `gno.land/r/...`; stateless reusable packages
  live under `gno.land/p/...`.
- The ZKGM proxy source tree and module path live under
  `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/`; the current implementation
  lives under `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/`.
- `make vendor` is idempotent and safe to run before tests. Mirrored
  third-party packages are generated workspace inputs; their submodule pins are
  the source of truth.

## Comparing Against IBC Union

When changing core, ZKGM, or access behavior, compare the Gno surface against
the pinned Union reference links collected in
[docs/ibc-union-spec-comparison.md](docs/ibc-union-spec-comparison.md) and
[docs/access-management.md](docs/access-management.md). Runtime wrapper
differences such as `cur realm`, direct function arguments, or absent CosmWasm
`Response` wrappers are expected Gno model differences unless they change state,
events, authorization, or protocol-visible data.

## Development References

- [Documentation index](docs/README.md)
- [TX Indexer Guide](docs/tx-indexer.md)
- [ZKGM Packet Send Guide](docs/zkgm-packet-send-guide.md)
- [ZKGM Batch Call-Recv Pattern](docs/zkgm-batch-call-recv.md)
- [IBC Native Function Gas Table](docs/ibc-native-gas.md)
- [Tools overview](tools/README.md)
- [Third-party mirror workflow](third_party/README.md)

## Reporting Failures

Use the repository's issue and pull request discussions for design questions,
bug reports, and review feedback. When reporting a failure, include the exact
command, the pinned Gno commit from `.gno-version`, and any relevant generated
fixture or packet data.
