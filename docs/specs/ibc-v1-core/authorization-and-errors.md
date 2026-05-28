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

## Errors

Core panics on validation failure. Public mutating entry points do not return
`error`. Error sentinels are defined in
[`gno.land/r/core/ibc/v1/core/state.gno`](../../../gno.land/r/core/ibc/v1/core/state.gno).
