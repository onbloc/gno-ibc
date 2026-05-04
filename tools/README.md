# tools

Auxiliary tools that support development and testing but are not part of the on-chain code. Each subdirectory is self-contained — see its own README for details.

| Tool | Purpose |
|---|---|
| [`abi-fixtures/`](abi-fixtures/) | Rust harness that emits canonical Solidity ABI vectors for the gno `encoding/abi` codec to test against |

Tools may use languages and toolchains other than Gno (e.g. Rust, Go). They are invoked via `make` targets at the repo root.
