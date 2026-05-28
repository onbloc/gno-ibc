# App Interface

IBC applications register an implementation of `IApp` at their port id. Locally
owned ports normally use the app realm package path bytes as the port id.

```go
type IApp interface {
    OnChannelOpenInit(cur realm, connectionId ConnectionId, channelId ChannelId, version string, relayer address)
    OnChannelOpenTry(cur realm, connectionId ConnectionId, channelId ChannelId, version string, counterpartyVersion string, relayer address)
    OnChannelOpenAck(cur realm, channelId ChannelId, counterpartyChannelId ChannelId, counterpartyVersion string, relayer address)
    OnChannelOpenConfirm(cur realm, channelId ChannelId, relayer address)
    OnChannelCloseInit(cur realm, channelId ChannelId, relayer address)
    OnChannelCloseConfirm(cur realm, channelId ChannelId, relayer address)
    OnRecvPacket(cur realm, packet Packet, relayer address, relayerMsg []byte) RecvPacketResult
    OnIntentRecvPacket(cur realm, packet Packet, marketMaker address, marketMakerMsg []byte)
    OnAcknowledgementPacket(cur realm, packet Packet, acknowledgement []byte, relayer address)
    OnTimeoutPacket(cur realm, packet Packet, relayer address)
}
```

All callbacks take `cur realm` as the first argument. Core invokes application
callbacks with `cross(cur)`, so the callback runs in the application realm and
can mutate application state.

An app type must satisfy the `core.IApp` interface before it can be registered
with `RegisterApp`.

Callback dispatch uses the port id registered through `RegisterApp`. Missing
app registrations panic with `ErrPortNotFound`. For channel-owned packet paths,
core first resolves the channel owner and then looks up the app by that port id.

| Callback | Core entry point | Core has already done | Core does after |
|----------|------------------|-----------------------|-----------------|
| `OnChannelOpenInit` | `ChannelOpenInit` | Allocated `channelId` and recorded the channel owner. | Saves the channel in `Init` state and emits `ChannelOpenInit`. |
| `OnChannelOpenTry` | `ChannelOpenTry` | Verified the counterparty `Init` proof, allocated `channelId`, and recorded the channel owner. | Saves the channel in `TryOpen` state and emits `ChannelOpenTry`. |
| `OnChannelOpenAck` | `ChannelOpenAck` | Verified the counterparty `TryOpen` proof. | Transitions the channel to `Open`, stores the counterparty channel id and version, and emits `ChannelOpenAck`. |
| `OnChannelOpenConfirm` | `ChannelOpenConfirm` | Verified the counterparty `Open` proof. | Transitions the channel to `Open` and emits `ChannelOpenConfirm`. |
| `OnChannelCloseInit` | `ChannelCloseInit` | Nothing. The entry point panics immediately. | Unreachable. |
| `OnChannelCloseConfirm` | `ChannelCloseConfirm` | Nothing. The entry point panics immediately. | Unreachable. |
| `OnRecvPacket` | `PacketRecv` | Verified the packet batch membership proof, checked the channel, timeout, and replay receipt. | Handles `RecvPacketResult`, commits sync acks when needed, and emits `PacketRecv`. |
| `OnIntentRecvPacket` | `IntentPacketRecv` | Checked the channel, timeout, and replay receipt. | Emits `IntentPacketRecv`. |
| `OnAcknowledgementPacket` | `PacketAcknowledgement` | Verified acknowledgement membership and found an outstanding source commitment. | Deletes the source packet commitment and emits `PacketAck`. |
| `OnTimeoutPacket` | `PacketTimeout` | Verified timeout eligibility and receipt non-membership. | Deletes the source packet commitment and emits `PacketTimeout`. |

If a callback panics, the transaction aborts and core does not keep partial
state changes from that entry point.

`OnRecvPacket` returns a `RecvPacketResult`:

```go
type PacketStatus uint8

const (
    PacketStatusUnknown PacketStatus = 0
    PacketStatusSuccess PacketStatus = 1
    PacketStatusFailure PacketStatus = 2
    PacketStatusAsync   PacketStatus = 3
)

type RecvPacketResult struct {
    Status PacketStatus
    Ack    []byte
}
```

| Status | Ack requirement | Core action |
|--------|-----------------|-------------|
| `PacketStatusAsync` | Ignored. | Records a receipt without committing the final acknowledgement. |
| `PacketStatusSuccess` | Non-empty. | Commits the ack and emits `WriteAck` in the receive transaction. |
| `PacketStatusFailure` | Non-empty. | Commits the ack and emits `WriteAck` in the receive transaction. |
| `PacketStatusUnknown` | N/A. | Always panics with `ErrUnknownPacketStatus`. |

`PacketStatusSuccess` and `PacketStatusFailure` with an empty `Ack` panic with
`ErrSyncAckEmpty`. Apps that need delayed acknowledgement semantics must return
`PacketStatusAsync` and later commit an acknowledgement through
`WriteAcknowledgement` or `BatchAcks`.

Apps in other realms should construct results with
`core.NewRecvPacketResult(cross(cur), status, ack)` instead of allocating
`RecvPacketResult` directly. This keeps the result construction inside the core
realm crossing frame.

`WriteAcknowledgement` and `BatchAcks` are the async ack writers. Both require
the caller realm to match the destination channel owner. `WriteAcknowledgement`
also rejects empty acknowledgements and already-written acknowledgements.

`IntentPacketRecv` is asymmetric with normal receive. It does not verify a
source-chain membership proof, does not return `RecvPacketResult`, and does not
write an acknowledgement by itself. Its event uses `market_maker_msg` where
normal receive uses `maker_msg`.

Channel close callbacks are declared only to satisfy the interface. The current
`ChannelCloseInit` and `ChannelCloseConfirm` entry points panic before callback
dispatch, and no code writes `ChannelStateClosed`.
