# Documentation

- [IBC Union Spec Comparison](ibc-union-spec-comparison.md) — entry point for
  comparing Gno public surfaces with the pinned IBC Union Core, ZKGM, and app
  callback message/query surfaces
- [Access Management Comparison](access-management.md) — map from the pure
  `p/onbloc/access/manager` package and shared access realm to OpenZeppelin and
  Union access-manager/access-managed references
- [TX Indexer Guide](tx-indexer.md) — querying IBC transactions and events via the deployed tx-indexer
- [IBC Native Function Gas Table](ibc-native-gas.md) — calibrated gas costs for the IBC / CometBLS native bindings registered in `gnovm/stdlibs/native_gas.go`
- [ZKGM Packet Send Guide](zkgm-packet-send-guide.md) — index for common SendRaw steps and per-kind TokenOrderV2 INITIALIZE / ESCROW procedures
- [ZKGM Batch Call-Recv Pattern](zkgm-batch-call-recv.md) — Osmosis-style "transfer and execute" via an OP_BATCH of TOKEN_ORDER + CALL, with receiver registration and send examples
