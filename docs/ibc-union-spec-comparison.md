# IBC Union Spec Surface Comparison

This document is the cross-module entry point for comparing the Gno public
surface in this repository with pinned IBC Union CosmWasm references. The
module README files keep the detailed tables; this page explains where to look
and how to interpret Gno-specific boundaries.

## Reference Sources

| Area | Union source | Gno comparison anchor |
| --- | --- | --- |
| Core execute/admin messages | [core msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/msg.rs) | [core realm surface](../gno.land/r/onbloc/ibc/union/core/README.md) |
| Core queries | [core query.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/query.rs) | [core query surface](../gno.land/r/onbloc/ibc/union/core/README.md#query) |
| Core app callbacks | [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs) | [ZKGM app callbacks](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md#ibc-union-app-callbacks) |
| UCS03-ZKGM execute/admin messages | [ZKGM msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs) | [ZKGM proxy surface](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md) |
| UCS03-ZKGM queries | [ZKGM msg.rs QueryMsg](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L203-L240) | [ZKGM query surface](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md#query) |
| Access manager model | [Union access-manager](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager) | [access management comparison](access-management.md) |

## How To Read The Tables

The per-module tables use Union message or query variants as the row source.
`-` in the Gno column means this repository does not expose a matching public
Gno surface. It can also mean the Union row is a CosmWasm-only lifecycle,
self-call, or migration surface that is intentionally replaced by a Gno realm
boundary.

Runtime shape differences are expected when they only reflect Gno execution:

- `cur realm` replaces CosmWasm `DepsMut`, `Env`, `MessageInfo`, and contract
  address context.
- Public Gno functions use typed arguments directly instead of an outer
  `ExecuteMsg` or `QueryMsg` enum.
- Gno functions return typed values or panic on failure instead of returning a
  CosmWasm `Response`.
- Proxy implementation upgrades are local realm lifecycle surfaces, even when
  they correspond to Union `Upgradable` wrappers.

State transitions, proof verification, event content, authorization, packet
commitments, and query-visible data are protocol comparison points. Treat drift
there as meaningful unless the module README states an intentional Gno model
difference.

## Surface Index

| Gno module | Detailed comparison | Union row source | Notes |
| --- | --- | --- | --- |
| Core proxy realm | [core README](../gno.land/r/onbloc/ibc/union/core/README.md#ibc-union-spec-surface-index) | `ExecuteMsg`, `RestrictedExecuteMsg`, `QueryMsg` | Covers client, connection, channel, packet/proof, query, and admin surfaces. |
| UCS03-ZKGM proxy realm | [ZKGM README](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md#ibc-union-spec-surface-index) | `ExecuteMsg`, `SendMsg`, `IbcUnionMsg`, `RestrictedExecuteMsg`, `QueryMsg` | Covers user send, core callbacks, query, pausable, rate-limit, and admin surfaces. |
| Shared access realm | [access README](../gno.land/r/onbloc/ibc/union/access/README.md) | `access-manager`, `access-managed`, deployer selector wiring | Provides the authority and selector gates used by core and ZKGM. |
| Pure access manager package | [package README](../gno.land/p/onbloc/access/manager/README.md) | OpenZeppelin `AccessManager`, Union `access-manager` | Stateless state-transition library used by the shared access realm. |

Implementation-level ZKGM differences that are not visible from message
variants alone are tracked in the [ZKGM implementation table](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md#implementation-level-union-differences).

## Admin And Access Boundary

Union nests `access_managed::ExecuteMsg`, `access_managed::QueryMsg`,
`Restricted<...>`, `Pausable`, and `Upgradable` wrappers into each contract's
message surface. Gno splits those concerns across realm boundaries:

| Union boundary | Gno boundary | Comparison doc |
| --- | --- | --- |
| `AccessManaged` execute/query wrappers | Shared [access realm](../gno.land/r/onbloc/ibc/union/access/README.md) and per-realm selector gates | [Access management comparison](access-management.md) |
| `Restricted<RestrictedExecuteMsg>` | Public functions guarded by selector checks | Core and ZKGM README admin rows |
| `Upgradable` | Proxy `UpdateImpl` lifecycle functions | Core and ZKGM README admin rows |
| `Pausable` | ZKGM proxy pause/admin surface | [ZKGM admin table](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md#admin) |

## Intentional Non-Message Surfaces

Some local functions are useful Gno integration points but are not IBC Union
message rows. They should stay out of message-variant comparison tables unless
the Union reference adds an equivalent public message:

- app registration helpers such as `RegisterApp`, `RegisterAppForPort`, and
  `HasApp`;
- proxy lifecycle helpers such as implementation registration and render
  functions;
- local realm render output;
- package-level constructors, typed helpers, and pure derivation functions such
  as ZKGM wrapped-token prediction helpers.
