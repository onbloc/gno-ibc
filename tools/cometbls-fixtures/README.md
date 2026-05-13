# cometbls-fixtures

Generates deterministic synthetic ICS-23 proof/root fixtures for the CometBLS
light client tests.

The fixtures are intentionally minimal: two-level proofs for the adapter path
`["wasm", wasmContractStoreKey(contractAddress, key)]`, where the leaf proof
uses the SDK IAVL proof spec and the store proof uses the Tendermint proof
spec. The generated membership cases cover representative packet, connection,
and channel key/value pairs in one shared IAVL subtree/root.

The packet case also emits a deterministic non-membership proof for
`packet-key-missing`. It reuses the packet leaf as the right-most left neighbor
in the IAVL subtree, then proves that subtree under the `wasm` store root.

Run:

```sh
go run .
```

## Consumers

When fixtures change, update and re-verify these files (each derives expected
key/value bytes from production path/encoding code so drift surfaces fast):

- `gno.land/p/core/ibc/lightclients/cometbls/synthetic_fixture_test.gno` —
  mirrors `synthetic*` proofs and roots.
- `gno.land/r/core/ibc/v1/apps/zkgm/testing/realcometbls/fixtures.gno` — byte
  literals consumed by all `realcometbls` scenarios.
- Sibling fixture-input filetests under
  `gno.land/r/core/ibc/v1/apps/zkgm/testing/realcometbls/scenarios/` and
  `gno.land/r/core/ibc/v1/core/` (z35, z36/z37 packet-lifecycle, z39, z40,
  z42).
