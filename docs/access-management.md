# Access Management Comparison

This document explains how the Gno access-management pieces map to the
OpenZeppelin and Union models. It is meant to be read before comparing the
`AccessManaged`, `Restricted`, and admin rows in the core and ZKGM README
surface tables.

## Components

| Gno component | Role | Primary references |
| --- | --- | --- |
| [p/onbloc/access/manager](../gno.land/p/onbloc/access/manager/README.md) | Stateless state-transition library for roles, target/function roles, target closure, and immediate authorization checks. | [OpenZeppelin AccessManager](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager), [Union access-manager](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager) |
| [r/onbloc/ibc/union/access](../gno.land/r/onbloc/ibc/union/access/README.md) | Stateful authority realm that owns `manager.State`, emits management events, and exposes management/query functions. | [Union access-managed](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-managed), [Union core init](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L592-L604), [Union ZKGM init](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/app/ucs03-zkgm/src/contract.rs#L67-L75) |
| Core and ZKGM managed realms | Call `AssertCanCall` with their own `cur realm` and selector before protected entrypoints. | [core access.gno](../gno.land/r/onbloc/ibc/union/core/access.gno), [ZKGM access.gno](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/access.gno) |

## Model Mapping

| Model concept | OpenZeppelin / Union shape | Gno shape |
| --- | --- | --- |
| State owner | Access manager contract owns role and target state. | Shared access realm owns `manager.State`. |
| Pure state transitions | Implemented inside the contract module. | Implemented in `p/onbloc/access/manager`; no storage ownership or `cur realm` inspection. |
| Managed target | Contract address plus selector. | Realm package path plus selector. |
| Caller identity | CosmWasm sender / EVM caller context. | Derived from `cur.Previous().Address()` by the access realm. |
| Authorization check | `AccessManaged` and `Restricted` wrappers call the authority. | Managed realms call `AssertCanCall(0, cur, selector)`. |
| Public role | Always callable when target is open. | `PublicRole` is retained as `uint64 max`; target closure still blocks calls. |
| Admin role | `ADMIN_ROLE = 0`. | `AdminRole = 0`. |
| Grant delay | Retained by OpenZeppelin and Union. | Retained by `GrantDelay` and member activation time. |
| Delayed operation execution | OpenZeppelin and Union include scheduling/execution concepts. | Not implemented; Gno keeps grant delay only. |

## Implemented Gno Surfaces

| Category | Gno surfaces |
| --- | --- |
| Role membership | `GrantRole`, `RevokeRole`, `RenounceRole`, `HasRole` |
| Role configuration | `LabelRole`, `SetRoleAdmin`, `SetGrantDelay`, `GetRoleAdmin`, `GetRoleGrantDelay` |
| Target configuration | `SetFunctionRole`, `SetFunctionRoles`, `SetTargetClosed`, `GetFunctionRole`, `GetTargetFunctionRole`, `IsTargetClosed` |
| Authorization | `AssertCanCall`, `CanCall`, `IsAuthorized`, `CanAdminRole`, `CanManageTarget` |
| Events | `RoleLabel`, `RoleGranted`, `RoleRevoked`, `RoleAdminChanged`, `RoleGrantDelayChanged`, `TargetClosed`, `TargetFunctionRoleUpdated` |

The pure package defines the event schema, but the access realm emits events so
they are attributed to the realm that owns state.

## Intentional Gno Differences

- No instantiate message exists for Gno realms, so the access realm bootstraps
  `AdminRole` from `DefaultAdminAddress` during `init`.
- Union's `initial_authority` wiring is represented by the shared access realm
  and per-target selector configuration instead of each managed realm owning a
  nested authority instance.
- Delayed operation scheduling, execution, cancellation, guardian roles,
  operation nonce storage, execution IDs, and account execution delays are not
  exposed. They depend on callable execution contexts that are not part of the
  current Gno access realm.
- The deployer role policy is local deployment configuration. Current Gno role
  coverage adopts `AdminRole`, core `RelayerRole`, and `PublicRole`; ZKGM
  `PAUSER`, `UNPAUSER`, and `RATE_LIMITER` role ids are documented but not
  ported until the matching selector groups and tests are introduced.

## Reading Core And ZKGM Admin Rows

When a core or ZKGM README row says `ExecuteMsg::AccessManaged`,
`ExecuteMsg::Restricted`, or `QueryMsg::AccessManaged`, compare it against this
access boundary instead of looking for a same-named Gno function. The equivalent
Gno behavior is split across:

- the shared access realm management/query surface;
- the managed realm's selector constants and access gates;
- the public entrypoint guarded by that selector.
