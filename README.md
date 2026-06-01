# gno-ibc

`gno-ibc` is a development workspace for bringing Union-compatible IBC
components to Gno. It contains first-party Gno packages and realms for the v1
IBC core, CometBLS and state-lens light clients, and the UCS03 ZKGM app, along
with the fixture generators and tooling needed to test them.

Use this repository to build and test Gno-side IBC behavior against Union wire
formats, proof fixtures, and operational packet flows. It is intended for
contributors working on the Gno IBC implementation, ZKGM packet handling,
light-client verification, and related tooling.

## Repository Layout

| Path | Contents |
|---|---|
| `gno.land/p/core/` | First-party stateless Gno packages: ABI/RLP codecs, Ethereum MPT/storage helpers, ZKGM ABI/types, token bucket logic, and light-client primitives. |
| `gno.land/r/core/ibc/v1/` | First-party stateful realms: v1 IBC core, light-client adapters, ZKGM proxy, implementation, loader, and test realms. |
| `tools/` | Fixture generators, protocol-code generation, and smoke-test scripts. |
| `third_party/` | Sparse-checkout submodules mirrored into `gno.land/` by `make vendor`. |
| `docs/` | Operational guides for tx-indexer queries, ZKGM packet sends, and native gas calibration. |

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
make refresh-abi-vectors       # regenerate Solidity ABI ground-truth vectors
make refresh-zkgm-scenarios    # regenerate ZKGM handler scenario fixtures
make generate-check            # verify generated protobuf codecs are current
```

Focused Gno test runs are also useful during development:

```bash
gno test -v ./gno.land/r/core/ibc/v1/core
gno test -v ./gno.land/r/core/ibc/v1/apps/zkgm/v0/impl
gno test -v ./gno.land/p/core/ibc/zkgm
```

## Development Notes

- `.gno` files are Gno, not Go. Use `gnomod.toml` module manifests and
  `gno.land/p/...` or `gno.land/r/...` import paths.
- The ZKGM source tree lives under `gno.land/r/core/ibc/v1/apps/zkgm/`, while
  its module/import path is `gno.land/r/gnoswap/ibc/v1/apps/zkgm`.
- `make vendor` is idempotent and safe to run before tests. Mirrored
  third-party packages are generated workspace inputs; their submodule pins are
  the source of truth.

For detailed agent and contribution conventions, see [AGENTS.md](AGENTS.md).

## Documentation

- [Documentation index](docs/README.md)
- [TX Indexer Guide](docs/tx-indexer.md)
- [ZKGM Packet Send Guide](docs/zkgm-packet-send-guide.md)
- [ZKGM Batch Call-Recv Pattern](docs/zkgm-batch-call-recv.md)
- [IBC Native Function Gas Table](docs/ibc-native-gas.md)
- [Tools overview](tools/README.md)
- [Third-party mirror workflow](third_party/README.md)

## Getting Help

Use the repository's issue and pull request discussions for design questions,
bug reports, and review feedback. When reporting a failure, include the exact
command, the pinned Gno commit from `.gno-version`, and any relevant generated
fixture or packet data.

## License

This repository is licensed under Apache-2.0 or MIT. See
[LICENSE-APACHE](LICENSE-APACHE) and [LICENSE-MIT](LICENSE-MIT).
