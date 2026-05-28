# Authorization Model

Packet authorization is based on the previous realm package path.

`PacketSend` and `BatchSend` require the caller realm to match the source
channel owner. `WriteAcknowledgement` and `BatchAcks` require the caller realm
to match the destination channel owner.

`PacketRecv`, `IntentPacketRecv`, `PacketAcknowledgement`, and `PacketTimeout`
have no caller authorization check. Their safety comes from proof verification
against the registered light client and from packet commitment or receipt state.

`ForceUpdateClient` is restricted to the deployer captured at core init and
also requires `runtime.AssertOriginCall()`. This prevents an intermediate realm
from reusing the deployer's origin identity.

Light-client and app callbacks are invoked through `cross(cur)`, so the target
realm can mutate its own state while core preserves the call boundary.

## Error Catalog

Core panics on validation failure. Public mutating entry points do not return
`error`. Error sentinels are defined in `state.gno` and are usually panicked
directly.

| Error | Meaning |
|-------|---------|
| `ErrClientTypeAlreadyRegistered` | Client type registration collision |
| `ErrClientTypeNotFound` | Create or lookup for an unknown client type |
| `ErrClientNotFound` | Lookup for an unknown client id |
| `ErrConsensusStateNotFound` | Lookup for a missing consensus state |
| `ErrConnectionNotFound` | Lookup for an unknown connection |
| `ErrInvalidConnectionState` | Connection state machine violation |
| `ErrChannelNotFound` | Lookup for an unknown channel |
| `ErrInvalidChannelState` | Channel state machine violation |
| `ErrPortNotFound` | App lookup for an unknown port id |
| `ErrSyncAckEmpty` | App returned a sync status with an empty ack |
| `ErrUnknownPacketStatus` | App returned an unrecognized packet status |
| `ErrUnauthorizedAckWriter` | Caller does not own the destination channel port |
| `ErrAcknowledgementAlreadyWritten` | Ack write attempted after an ack already exists |
| `ErrAcknowledgementEmpty` | Ack write attempted with empty ack bytes |
| `ErrUnauthorizedPacketSender` | Caller does not own the source channel port |
| `ErrNotEnoughPackets` | Batch or receive entry point was called with no packets |
| `ErrBatchSameChannelOnly` | Batch contains packets from different relevant channels |
| `ErrAcknowledgementCountMismatch` | Packet count and ack count differ |
| `ErrPortAlreadyRegistered` | App port registration collision |
| `ErrBatchPacketsNotFound` | Internal packet batch lookup failed |
| `ErrBatchReceiptsNotFound` | Internal receipt batch lookup failed |
| `ErrPacketTimeoutExpired` | Receive attempted after packet timeout |
| `ErrPacketTimeoutNotReached` | Timeout attempted before packet timeout |
