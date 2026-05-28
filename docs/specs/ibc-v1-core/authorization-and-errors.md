# Authorization Model

Packet authorization is based on the previous realm package path.

`PacketSend` and `BatchSend` require the caller realm to match the source
channel owner. `WriteAcknowledgement` and `BatchAcks` require the caller realm
to match the destination channel owner.

`PacketRecv`, `PacketAcknowledgement`, and `PacketTimeout` have no caller
authorization check. Their safety comes from membership or non-membership
proof verification against the registered counterparty light client.

`IntentPacketRecv` also has no caller authorization check, but it does not
verify a source-chain proof either. Its safety comes from receipt replay
protection and from the application callback, which decides whether the
proposed intent is acceptable.

`ForceUpdateClient` is restricted to the deployer captured at core init and
also requires `runtime.AssertOriginCall()`. This prevents an intermediate realm
from reusing the deployer's origin identity.

Light-client and app callbacks are invoked through `cross(cur)`, so the target
realm can mutate its own state while core preserves the call boundary.

## Error Catalog

Core panics on validation failure. Public mutating entry points do not return
`error`. Error sentinels are defined in `state.gno` and are usually panicked
directly.

| Error | Raised by | Meaning |
|-------|-----------|---------|
| `ErrClientTypeAlreadyRegistered` | `RegisterClient` | Client type registration collision. |
| `ErrClientTypeNotFound` | `CreateClient` | Create or lookup for an unknown client type. |
| `ErrClientNotFound` | client and proof entry points | Lookup for an unknown client id. |
| `ErrConsensusStateNotFound` | proof entry points | Lookup for a missing consensus state. |
| `ErrConnectionNotFound` | connection and channel entry points | Lookup for an unknown connection. |
| `ErrInvalidConnectionState` | `ConnectionOpen*` | Connection state-machine violation. |
| `ErrChannelNotFound` | channel and packet entry points | Lookup for an unknown channel. |
| `ErrInvalidChannelState` | `ChannelOpen*` and packet entry points | Channel state-machine violation. |
| `ErrPortNotFound` | callback dispatch | App lookup for an unknown port id. |
| `ErrSyncAckEmpty` | `PacketRecv` | App returned a sync status with an empty ack. |
| `ErrUnknownPacketStatus` | `PacketRecv` | App returned an unrecognized packet status. |
| `ErrUnauthorizedAckWriter` | `WriteAcknowledgement`, `BatchAcks` | Caller does not own the destination channel port. |
| `ErrAcknowledgementAlreadyWritten` | `WriteAcknowledgement` | Ack write attempted after an ack already exists. |
| `ErrAcknowledgementEmpty` | `WriteAcknowledgement` | Ack write attempted with empty ack bytes. |
| `ErrUnauthorizedPacketSender` | `PacketSend`, `BatchSend` | Caller does not own the source channel port. |
| `ErrNotEnoughPackets` | `BatchSend`, `PacketRecv` | Batch or receive entry point was called with no packets. |
| `ErrBatchSameChannelOnly` | `BatchSend`, `PacketRecv` | Batch contains packets from different relevant channels. |
| `ErrAcknowledgementCountMismatch` | `BatchAcks` | Packet count and ack count differ. |
| `ErrPortAlreadyRegistered` | `RegisterApp` | App port registration collision. |
| `ErrBatchPacketsNotFound` | `PacketAcknowledgement`, `PacketTimeout` | Internal packet batch lookup failed. |
| `ErrBatchReceiptsNotFound` | `PacketAcknowledgement` | Internal receipt batch lookup failed. |
| `ErrPacketTimeoutExpired` | `PacketRecv` | Receive attempted after packet timeout. |
| `ErrPacketTimeoutNotReached` | `PacketTimeout` | Timeout attempted before packet timeout. |
