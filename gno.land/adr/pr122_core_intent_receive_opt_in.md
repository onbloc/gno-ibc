# Core Intent Receive Opt-In

The v1 IBC core realm exposes application callbacks through `IApp`.

`IntentPacketRecv` is a specialized receive path used by applications that support market-maker intent semantics. Before this change, its callback was part of the generic `IApp` interface, so every registered app had to implement the method even if it did not support intent receive.

## Decision

Move `OnIntentRecvPacket` out of `IApp` and into a separate `IIntentApp` interface.

Require applications to explicitly implement `IIntentApp` to participate in intent receive processing.

Applications that support intent receive may implement both `IApp` and `IIntentApp`.
