# Query Surface

The proxy exposes a limited public query surface:

| Function | Behavior |
|----------|----------|
| `GetConfig()` | Returns `Config{ImplPath, AllowedImpls, Paused}`. |
| `Render(path)` | Returns `zkgm: impl not set` when no impl is installed, otherwise delegates to `impl.Render(ProxyPkgPath(), path)`. |

The v0 implementation renders `zkgm v1` for an empty path. Any non-empty path
returns `zkgm/v1: render path not found: <path>`.

There are no public proxy query helpers for channel balances, receivers, or
token buckets. Ledger getters exist for implementation use and may not be a
complete relayer or indexer surface.

## Events

ZKGM packet activity is observed through IBC core events such as `PacketSend`,
`BatchSend`, `PacketRecv`, `WriteAck`, `PacketAck`, and `PacketTimeout`.
Reserved ZKGM-specific forward-child event constants exist in the ABI package,
but the current implementation does not emit them.

See [Event Catalog](../events.md) for the current event list and attributes.

## Implementation Differences

The current implementation has these intentional boundaries:

| Area | Current behavior |
|------|------------------|
| Proxy model | ZKGM uses a hot-swappable proxy plus implementation split. |
| Channel version | The required version is `ucs03-zkgm-0`. |
| Native sends | Native attached coins require a direct user call. |
| Token order shape | `TokenOrderV2` is active. `TokenOrderV1` remains for legacy decoding and fixtures. |
| SOLVE | Defined but not implemented. |
| Batch children | Only `OP_CALL` and `OP_TOKEN_ORDER` are accepted. |
| Forward children | `OP_CALL`, `OP_TOKEN_ORDER`, and `OP_BATCH` are accepted. Direct `OP_FORWARD` is rejected. |
| Forward send | Child packets are sent through one-packet `BatchSend`. |
| Rate limiting | Applied inside TokenOrderV2 verification only. |
| Events | ZKGM-specific forward events are reserved but not emitted. |
| Channel close | The app exposes close callbacks, but IBC core channel close entry points currently panic as unsupported. |

Out-of-scope behavior includes ordered channel semantics, multi-payload async
acks, deferred multi-hop parent ack propagation beyond the current in-flight
record and `WriteForwardAck` path, and a channel registry for receiver discovery
beyond pkgpath registration.

## Maintenance Notes

This spec tracks current implementation behavior only. Keep historical design
notes and uncommitted design material out of this document. When implementation
behavior changes, update this spec together with the code or test that proves
the new behavior.
