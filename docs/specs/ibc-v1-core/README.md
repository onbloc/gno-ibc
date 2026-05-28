# IBC v1 Core Spec

This document describes the current IBC v1 core realm implementation under
[gno.land/r/core/ibc/v1/core](../../../gno.land/r/core/ibc/v1/core).

## Scope

The core realm owns the IBC state machine for:

- light-client registration and client lifecycle
- connection and channel handshakes
- packet commitments, receipts, acknowledgements, and timeouts
- application registration and callback dispatch
- events emitted for relayers and indexers

The implementation is a Gno realm. Entry points that mutate core state take
`cur realm` and are invoked from other realms with `cross(cur)`.

## Module Layout

The core realm is published as `gno.land/r/core/ibc/v1/core` and its module path
matches the filesystem path.

| File | Purpose |
|------|---------|
| `core.gno` | State construction, interface definitions, app registration, commitment helpers, and render output |
| `types.gno` | Domain types, enums, string rendering, and ABI encoding helpers |
| `msg.gno` | Message structs for public entry points |
| `path.gno` | Commitment namespace constants, path derivation, and sentinel values |
| `commit.gno` | Packet, packet batch, and acknowledgement hashing |
| `state.gno` | Core state stores, save helpers, query helpers, and error sentinels |
| `client.gno` | Client lifecycle, client registration, and client queries |
| `connection.gno` | Connection handshake and connection query |
| `channel.gno` | Channel handshake, channel close stubs, channel query, and channel getter |
| `packet.gno` | Packet send, receive, acknowledgement, timeout, batch, and query entry points |
| `events.gno` | Event constants and emitter helpers |

## Registered Interfaces

Light clients are registered by client type through `RegisterClient`. The core
stores the adapter instance and delegates create, update, status, membership,
and non-membership verification to that adapter.

Applications are registered by port path through `RegisterApp`. Channel and
packet entry points use the previous realm package path as the application
identity, so app realms must call core entry points directly rather than through
unregistered helper realms.

The core-facing light-client interface contains create, update, membership
verification, non-membership verification, timestamp, latest-height, and status
methods. `IForceLightClient` is an optional extension used only by
`ForceUpdateClient`.

The app interface contains channel-open callbacks, packet receive callbacks,
intent receive callbacks, acknowledgement callbacks, and timeout callbacks.
`Send` is not part of the core app callback interface. Apps call core send entry
points directly.

`RegisterClient`, `RegisterApp`, `CreateClient`, `UpdateClient`, connection
handshake entry points, and channel handshake entry points are not admin-gated.
They are open protocol entry points whose safety comes from adapter
registration, proof verification, and state-machine checks.

## Module Reference

| File | Topic |
| --- | --- |
| [App Interface](./app-interface.md) | IBCApp interface and port binding |
| [Domain Types and Encoding](./domain-types-and-encoding.md) | Core structs and ABI encoding |
| [Store and Paths](./store-and-paths.md) | AVL store layout and commitment paths |
| [Client Lifecycle](./client-lifecycle.md) | CreateClient, UpdateClient, Misbehaviour |
| [Connection and Channel Lifecycle](./connection-channel-lifecycle.md) | Handshake state machines |
| [Packet Lifecycle](./packet-lifecycle.md) | Send, Recv, Acknowledge, Timeout |
| [Authorization and Errors](./authorization-and-errors.md) | Authorization roles and error catalog |
| [Queries, Events, Differences](./queries-events-differences.md) | Query RPCs, events, ibc-go deltas |
