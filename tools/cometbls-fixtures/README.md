# cometbls-fixtures

Generates deterministic synthetic ICS-23 proof/root fixtures for the CometBLS
light client tests.

The initial fixtures are intentionally minimal: two-level membership proofs for
the adapter path `["ibc", key]`, where the leaf proof uses the SDK IAVL proof
spec and the store proof uses the Tendermint proof spec. The generated cases
cover representative packet, connection, and channel key/value pairs.

Run:

```sh
go run .
```
