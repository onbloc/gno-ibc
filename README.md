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
| `gno.land/p/onbloc/` | First-party stateless Gno packages: ABI/RLP codecs, Ethereum MPT/storage helpers, ZKGM ABI/types, token bucket logic, access helpers, and light-client primitives. |
| `gno.land/r/onbloc/ibc/union/` | First-party stateful realms: Union IBC core, light-client-facing apps, UCS03 ZKGM proxy/implementation, and test realms. |
| `tools/` | Fixture generators, protocol-code generation, and smoke-test scripts. |
| `third_party/` | Sparse-checkout submodules mirrored into `gno.land/` by `make vendor`. |
| `docs/` | Cross-module references, Union spec comparison notes, operational guides, and gas calibration. |

## Main Surfaces

- [IBC Union core proxy realm](gno.land/r/onbloc/ibc/union/core/README.md)
- [IBC Union UCS03-ZKGM proxy realm](gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md)
- [Union access realm](gno.land/r/onbloc/ibc/union/access/README.md)
- [Access manager pure package](gno.land/p/onbloc/access/manager/README.md)

## Documentation

- [Documentation index](docs/README.md)
- [IBC Union spec comparison](docs/ibc-union-spec-comparison.md)
- [Access management comparison](docs/access-management.md)
- [TX Indexer Guide](docs/tx-indexer.md)
- [ZKGM Packet Send Guide](docs/zkgm-packet-send-guide.md)
- [ZKGM Batch Call-Recv Pattern](docs/zkgm-batch-call-recv.md)
- [IBC Native Function Gas Table](docs/ibc-native-gas.md)
- [Tools overview](tools/README.md)
- [Third-party mirror workflow](third_party/README.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, validation commands, Gno
development notes, and reporting guidance. For agent-specific repository rules,
see [AGENTS.md](AGENTS.md).

## License

This repository is licensed under Apache-2.0 or MIT. See
[LICENSE-APACHE](LICENSE-APACHE) and [LICENSE-MIT](LICENSE-MIT).
