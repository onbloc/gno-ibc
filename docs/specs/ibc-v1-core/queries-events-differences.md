# Query Surface

Prefer safe query and `Has*` helpers for relayer-style reads. `Get*` helpers may
panic on missing state.

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

`Render(path)` is intended for web or bootstrap diagnostics. It ignores the
input path and returns a summary containing the next client id and registered
client types.

```text
next client id: <N>
registered clients: [ <type1> <type2> ... ]
```

## Events

Core emits PascalCase event types. Current public event names include:

| Area | Events |
|------|--------|
| Clients | `CreateClient`, `UpdateClient` |
| Connections | `ConnectionOpenInit`, `ConnectionOpenTry`, `ConnectionOpenAck`, `ConnectionOpenConfirm` |
| Channels | `ChannelOpenInit`, `ChannelOpenTry`, `ChannelOpenAck`, `ChannelOpenConfirm` |
| Packets | `PacketSend`, `BatchSend`, `PacketRecv`, `IntentPacketRecv`, `WriteAck`, `PacketAck`, `PacketTimeout` |

Indexer-facing query examples are documented in
[docs/tx-indexer.md](../../tx-indexer.md).

The full event and attribute catalog is maintained in
[Event Catalog](../events.md).

Event attributes are emitted through helper functions in `events.gno` so
attribute lists remain consistent across call sites. Binary attributes use
lowercase `0x`-prefixed hex encoding.

## Implementation Differences

The current core intentionally differs from some older IBC expectations in a few
places:

- Packet identity is hash-based. There is no packet sequence field.
- Ordered channels are not implemented.
- Channel close is unsupported.
- Receipt and acknowledgement state share the `batchReceipts` store.
- Core does not route misbehaviour through `ILightClient`. Adapters may still
  expose internal misbehaviour handling, but core has no entry point that
  invokes it.

## Maintenance Notes

This spec should track current core behavior only. Keep historical notes out of
committed implementation specs.
