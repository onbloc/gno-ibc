# Authorization Model

Packet authorization is based on the previous realm package path.

`PacketSend` and `BatchSend` require the caller realm to match the source
channel owner. `WriteAcknowledgement` and `BatchAcks` require the caller realm
to match the destination channel owner and require an existing packet receipt.

`PacketRecv`, `PacketAcknowledgement`, and `PacketTimeout` have no caller
authorization check. Their safety comes from membership or non-membership
proof verification against the registered counterparty light client.

`IntentPacketRecv` also has no caller authorization check, but it does not
verify a source-chain proof either. It checks existing receipts to avoid
reprocessing packets that were already proven-received, but it does not write a
receipt. Its safety comes from the application callback, which decides whether
the proposed intent is acceptable.

Ordinary `RegisterApp` and `RegisterClient` are ownership-scoped. `RegisterApp`
binds the caller realm's package path as the app port. `RegisterClient` only
allows known production client types from their owning light-client realms, and
custom client types under the caller realm's package path.

`RegisterAppForPort`, `RegisterClientForType`, and `ForceUpdateClient` are
restricted to the deployer captured at core init and also require
`runtime.AssertOriginCall()`. This prevents an intermediate realm from reusing
the deployer's origin identity.

Light-client and app callbacks are invoked through `cross(cur)`, so the target
realm can mutate its own state while core preserves the call boundary.

## Errors

Core panics on validation failure. Public mutating entry points do not return
`error`. Error sentinels are defined in
[`gno.land/r/core/ibc/v1/core/state.gno`](../../../gno.land/r/core/ibc/v1/core/state.gno).
