# Core Surface and Deltas

This page covers the public query surface, the event surface, and the points
where core diverges from the ibc-go reference implementation.

## Query Surface

Prefer safe query and `Has*` helpers for relayer-style reads. `Get*` helpers
may panic on missing state.

Safe reads:

| Function | Return on miss |
|----------|----------------|
| `QueryClientState(clientId)` | empty string |
| `QueryConsensusState(clientId, height)` | empty string |
| `GetClientType(clientId)` | empty string |
| `GetClientStatus(clientId)` | `StatusUnknown` |
| `HasClient(clientType)` | `false` |
| `QueryConnection(connectionId)` | empty string |
| `QueryChannel(channelId)` | empty string |
| `QueryBatchPackets(batchHash)` | empty string |
| `QueryBatchReceipts(batchHash)` | empty string |
| `QueryCommitmentAtPath(path)` | empty string |
| `QueryReceiptAtPath(path)` | empty string |
| `HasPacketCommitment(_, packet)` | `false` |
| `HasPacketReceipt(_, packet)` | `false` |
| `HasAcknowledgement(_, packet)` | `false` |
| `AcknowledgementHash(_, packet)` | zero `H256` |
| `HasApp(portId)` | `false` |

Guarded reads:

| Function | Missing-state behavior |
|----------|------------------------|
| `GetChannel(channelId)` | panics with `ErrChannelNotFound` |

`Render(path)` is a web and bootstrap diagnostic. It currently ignores the
input path and always returns a fixed summary:

```text
next client id: <N>
registered clients: [ <type1> <type2> ... ]
```

The path argument is reserved for future per-resource rendering.

## Event Surface

Core emits PascalCase event types:

| Area | Events |
|------|--------|
| Clients | `CreateClient`, `UpdateClient` |
| Connections | `ConnectionOpenInit`, `ConnectionOpenTry`, `ConnectionOpenAck`, `ConnectionOpenConfirm` |
| Channels | `ChannelOpenInit`, `ChannelOpenTry`, `ChannelOpenAck`, `ChannelOpenConfirm` |
| Packets | `PacketSend`, `BatchSend`, `PacketRecv`, `IntentPacketRecv`, `WriteAck`, `PacketAck`, `PacketTimeout` |

Event attributes are emitted through helper functions in `events.gno` so
attribute lists stay consistent across call sites. Binary attributes use
lowercase `0x`-prefixed hex encoding. The full attribute catalog is in
[Event Catalog](../events.md), and indexer query examples are in
[docs/tx-indexer.md](../../tx-indexer.md).

## Differences from ibc-go

Core intentionally departs from ibc-go in the following places:

- **Packet identity is hash-based.** There is no packet sequence field.
- **Ordered channels are not implemented.** All channels behave like ibc-go's
  `UNORDERED`.
- **Channel close is unsupported.** Close entry points panic before any state
  mutation.
- **Receipt and acknowledgement state share one store.** Both live in
  `batchReceipts`, distinguished by sentinel values.
- **Misbehaviour is not routed through `ILightClient`.** Adapters may still
  expose internal misbehaviour handling, but core has no entry point that
  invokes it.
