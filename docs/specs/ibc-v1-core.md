# IBC v1 Core Spec

This document describes the current IBC v1 core realm implementation under
[gno.land/r/core/ibc/v1/core](../../gno.land/r/core/ibc/v1/core).

## Scope

The core realm owns the IBC state machine for:

- light-client registration and client lifecycle
- connection and channel handshakes
- packet commitments, receipts, acknowledgements, and timeouts
- application registration and callback dispatch
- events emitted for relayers and indexers

The implementation is a Gno realm. Entry points that mutate core state take
`cur realm` and are invoked from other realms with `cross(cur)`.

## Registered Interfaces

Light clients are registered by client type through `RegisterClient`. The core
stores the adapter instance and delegates create, update, status, membership,
and non-membership verification to that adapter.

Applications are registered by port path through `RegisterApp`. Channel and
packet entry points use the previous realm package path as the application
identity, so app realms must call core entry points directly rather than through
unregistered helper realms.

## Client Lifecycle

`CreateClient` allocates a client identifier for the requested client type,
delegates initialization to the registered light-client adapter, stores the
client state and initial consensus state, and emits `CreateClient`.

`UpdateClient` loads the registered adapter, delegates header verification and
state transition, persists the returned client state and consensus state, and
emits `UpdateClient`.

`ForceUpdateClient` is a deployer-only operational path. It requires an origin
call, requires the target adapter to support the force-update interface, and
then persists the adapter-provided state update.

Status-sensitive proof verification is enforced before membership or
non-membership verification. Core paths call light-client status checks before
delegating proof verification, and v1 adapters also guard their own proof
methods.

## Connection and Channel Lifecycle

Connections follow the standard four-step handshake:

- `ConnectionOpenInit`
- `ConnectionOpenTry`
- `ConnectionOpenAck`
- `ConnectionOpenConfirm`

Channels follow the same handshake shape:

- `ChannelOpenInit`
- `ChannelOpenTry`
- `ChannelOpenAck`
- `ChannelOpenConfirm`

`ChannelOpenInit` records the calling app realm as the source port owner. The
counterparty channel identifier is only known after later handshake steps, so
the init event does not imply a final counterparty channel mapping.

Channel close entry points are present but unsupported. `ChannelCloseInit` and
`ChannelCloseConfirm` currently panic instead of transitioning channel state or
emitting close events.

## Packet Lifecycle

`PacketSend` validates that the caller owns the source port, verifies that the
channel is open, commits the packet, and emits `PacketSend`.

`BatchSend` validates a same-channel packet batch, commits all packet
commitments, emits `BatchSend`, and emits a per-packet `PacketSend` event.

`PacketRecv` verifies the packet batch proof against the destination channel's
client, rejects timed-out packets, skips packets that already have receipts,
dispatches `OnRecvPacket` to the destination app, and handles the returned
status:

- synchronous statuses write an acknowledgement immediately
- `PacketStatusAsync` records receipt state without writing the final
  acknowledgement

`IntentPacketRecv` is the market-maker receive path. It dispatches packet
handling without the normal proof and acknowledgement write flow.

`WriteAcknowledgement` is the async acknowledgement writer. Only the destination
app owner for the channel can write the acknowledgement.

`PacketAcknowledgement` verifies acknowledgement membership, deletes the source
packet commitment, dispatches the source app acknowledgement callback, and emits
`PacketAck`.

`PacketTimeout` verifies non-membership of the destination receipt after the
timeout condition is met, deletes the source packet commitment, dispatches the
source app timeout callback, and emits `PacketTimeout`.

## Events

Core emits PascalCase event types. Current public event names include:

| Area | Events |
|------|--------|
| Clients | `CreateClient`, `UpdateClient` |
| Connections | `ConnectionOpenInit`, `ConnectionOpenTry`, `ConnectionOpenAck`, `ConnectionOpenConfirm` |
| Channels | `ChannelOpenInit`, `ChannelOpenTry`, `ChannelOpenAck`, `ChannelOpenConfirm` |
| Packets | `PacketSend`, `BatchSend`, `PacketRecv`, `IntentPacketRecv`, `WriteAck`, `PacketAck`, `PacketTimeout` |

Indexer-facing query examples are documented in
[docs/tx-indexer.md](../tx-indexer.md).

The full event and attribute catalog is maintained in
[Event Catalog](events.md).

## Maintenance Notes

This spec should track current core behavior only. Keep historical planning
notes out of committed implementation specs.
