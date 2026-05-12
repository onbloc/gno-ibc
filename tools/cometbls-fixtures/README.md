# cometbls-fixtures

Generates deterministic synthetic ICS-23 proof/root fixtures for the CometBLS
light client tests.

The fixtures are intentionally minimal: two-level proofs for the adapter path
`["ibc", key]`, where the leaf proof uses the SDK IAVL proof spec and the store
proof uses the Tendermint proof spec. The generated membership cases cover
representative packet, connection, and channel key/value pairs.

The packet case also emits a deterministic non-membership proof for
`packet-key-missing`. It reuses the packet leaf as the left neighbor in the IAVL
subtree, then proves that subtree under the `ibc` store root.

Run:

```sh
go run .
```
