# tools

Auxiliary tools that support development and testing but are not part of the on-chain code. Each subdirectory is self-contained — see its own README for details.

| Tool | Purpose |
|---|---|
| [`abi-fixtures/`](abi-fixtures/) | Rust harness that emits canonical Solidity ABI vectors for the gno `encoding/abi` codec to test against |
| [`cometbls-fixtures/`](cometbls-fixtures/) | Go harness that emits synthetic ICS-23 proof/root vectors for CometBLS light client tests |
| [`gen-ethereum-storage-proof-fixture/`](gen-ethereum-storage-proof-fixture/) | Go harness that emits go-ethereum storage proof vectors for the Gno Ethereum storage verifier |
| [`zkgm-fixtures/`](zkgm-fixtures/) | Rust harness that emits handler/dispatch end-to-end ZKGM scenario fixtures (full `ZkgmPacket` + matching `Ack`) for the gno zkgm handler tests |

Tools may use languages and toolchains other than Gno (e.g. Rust, Go). They are invoked via `make` targets at the repo root.
