# IBC v1 Core Spec

This document describes the current IBC v1 core realm implementation under
[gno.land/r/core/ibc/v1/core](../../../gno.land/r/core/ibc/v1/core). The realm
is published at the same module path as its filesystem location.

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

Light clients are registered by client type through `RegisterClient` or the
deployer-only `RegisterClientForType`. Ordinary registration is constrained to
the owning light-client realm for known production client types, or to a client
type scoped under the caller realm's package path for custom types. Core stores
the adapter instance and delegates create, update, status, membership, and
non-membership verification to it.

Applications self-register at the caller realm package path through
`RegisterApp`. The deployer-only `RegisterAppForPort` path registers an
explicit port id for loader-style deployments. Channel and packet entry points
use the previous realm package path as the application identity, so app realms
must call core entry points directly rather than through unregistered helper
realms.

The core-facing light-client interface contains create, update, membership
verification, non-membership verification, timestamp, latest-height, and status
methods. `IForceLightClient` is an optional extension used only by
`ForceUpdateClient`.

The app interface contains channel-open callbacks, packet receive callbacks,
intent receive callbacks, acknowledgement callbacks, and timeout callbacks.
`Send` is not part of the core app callback interface. Apps call core send
entry points directly.

Authorization details for these entry points are catalogued in
[Authorization and Errors](./authorization-and-errors.md).

## Module Reference

| File | Topic |
| --- | --- |
| [App Interface](./app-interface.md) | `IApp` interface and port binding |
| [Domain Types and Encoding](./domain-types-and-encoding.md) | Core structs and ABI encoding |
| [Store and Paths](./store-and-paths.md) | In-memory stores and commitment path derivation |
| [Client Lifecycle](./client-lifecycle.md) | `CreateClient`, `UpdateClient`, `ForceUpdateClient` |
| [Connection and Channel Lifecycle](./connection-channel-lifecycle.md) | Handshake state machines |
| [Packet Lifecycle](./packet-lifecycle.md) | Send, receive, acknowledge, timeout |
| [Authorization and Errors](./authorization-and-errors.md) | Authorization roles and error catalog |
| [Surface and Deltas](./surface-and-deltas.md) | Query RPCs, events, and differences from ibc-go |
