# Documentation

## Architecture

- [Project Architecture](architecture/) — map of the first-party `onbloc`
  pure packages and realms, the proxy/implementation split, and how a packet
  flows through the layers
- [Process Flows](architecture/process-flows.md) — lifecycle flows for
  light-client registration, app registration, packet send, and packet receive

## Spec Comparisons

`spec-comparisons/` contains source-to-source comparison material for the Gno
implementation against pinned IBC Union, Union CosmWasm, and OpenZeppelin
references.

- [IBC Union Spec Comparison](spec-comparisons/ibc-union-spec-comparison.md) —
  entry point for comparing Gno public surfaces with the pinned IBC Union Core,
  ZKGM, and app callback message/query surfaces
- [Access Management Comparison](spec-comparisons/access-management.md) — map
  from the pure `p/onbloc/access/manager` package and shared access realm to
  OpenZeppelin and Union access-manager/access-managed references

## Guides

`guides/` contains operational guides and runbooks for working with deployed or
testnet flows.

- [TX Indexer Guide](guides/tx-indexer.md) — querying IBC transactions and
  events via the deployed tx-indexer
- [ZKGM Packet Send Guide](guides/zkgm-packet-send/) — index for common
  SendRaw steps and per-kind TokenOrderV2 INITIALIZE / ESCROW procedures

## References

`references/` contains standalone notes, gas tables, and implementation
patterns that support development or review but are not step-by-step guides.

- [IBC Native Function Gas Table](references/ibc-native-gas.md) — calibrated
  gas costs for the IBC / CometBLS native bindings registered in
  `gnovm/stdlibs/native_gas.go`
- [ZKGM Batch Call-Recv Pattern](references/zkgm-batch-call-recv.md) —
  Osmosis-style "transfer and execute" via an OP_BATCH of TOKEN_ORDER + CALL,
  with receiver registration and send examples
