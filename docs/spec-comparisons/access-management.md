# Access Management Comparison

This document explains how the Gno access-management pieces map to the
OpenZeppelin and Union models. It is meant to be read before comparing the
`AccessManaged`, `Restricted`, and admin rows in the core and ZKGM README
surface tables.

## Components

| Gno component | Role | Primary references |
| --- | --- | --- |
| [p/onbloc/access/manager](../../gno.land/p/onbloc/access/manager/README.md) | Stateless state-transition library for roles, target/function roles, target closure, immediate/delayed authorization checks, and scheduled operation state. | [OpenZeppelin AccessManager](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager), [Union access-manager](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager) |
| [r/onbloc/ibc/union/access](../../gno.land/r/onbloc/ibc/union/access/README.md) | Stateful authority realm that owns `manager.State`, emits management events, and exposes management/query functions. | [Union access-managed](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-managed), [Union core init](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L592-L604), [Union ZKGM init](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/app/ucs03-zkgm/src/contract.rs#L67-L75) |
| Core and ZKGM managed realms | Call `AssertCanCall` with their own `cur realm` and selector before protected entrypoints. | [core access.gno](../../gno.land/r/onbloc/ibc/union/core/access.gno), [ZKGM access.gno](../../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/access.gno) |

## Model Mapping

| Model concept | OpenZeppelin / Union shape | Gno shape |
| --- | --- | --- |
| State owner | Access manager contract owns role and target state. | Shared access realm owns `manager.State`. |
| Pure state transitions | Implemented inside the contract module. | Implemented in `p/onbloc/access/manager`; no storage ownership or `cur realm` inspection. |
| Managed target | Contract address plus selector. | Realm package path plus selector. |
| Caller identity | CosmWasm sender / EVM caller context. | Derived from `cur.Previous().Address()` by the access realm. |
| Authorization check | `AccessManaged` and `Restricted` wrappers call the authority. | Managed realms call `AssertCanCall(0, cur, selector)` for immediate-only gates or `AssertCanCallOrConsume(0, cur, selector, dataHash)` for delayed gates. |
| Public role | Always callable when target is open. | `PublicRole` is retained as `uint64 max`; target closure still blocks calls. |
| Admin role | `ADMIN_ROLE = 0`. | `AdminRole = 0`. |
| Grant delay | Retained by OpenZeppelin and Union. | Retained by `GrantDelay` and member activation time. |
| Execution delay | Role membership can require delayed execution. | `GrantRoleWithExecutionDelay` stores execution delay; `CanCall` reports delayed authorization. |
| Target admin delay | Target configuration can require a scheduled operation. | `SetTargetAdminDelay`, `ScheduleTargetAdmin`, and `Set*Delayed` consume scheduled target-admin operations. |
| Delayed operation execution | OpenZeppelin and Union schedule and execute encoded target calls through the manager. | Gno schedules/cancels/consumes operation state, but target execution happens by re-invoking the original realm function and consuming through its guard. |

## Implemented Gno Surfaces

| Category | Gno surfaces |
| --- | --- |
| Role membership | `GrantRole`, `GrantRoleWithExecutionDelay`, `RevokeRole`, `RenounceRole`, `HasRole` |
| Role configuration | `LabelRole`, `SetRoleAdmin`, `SetRoleGuardian`, `SetGrantDelay`, `GetRoleAdmin`, `GetRoleGuardian`, `GetRoleGrantDelay` |
| Target configuration | `SetFunctionRole`, `SetFunctionRoleDelayed`, `SetFunctionRoles`, `SetFunctionRolesDelayed`, `SetTargetAdminDelay`, `SetTargetAdminDelayDelayed`, `SetTargetClosed`, `SetTargetClosedDelayed`, `GetFunctionRole`, `GetTargetFunctionRole`, `GetTargetAdminDelay`, `IsTargetClosed` |
| Authorization | `AssertCanCall`, `AssertCanCallOrConsume`, `CanCall`, `IsAuthorized`, `CanAdminRole`, `CanManageTarget`, `CanManageTargetPath` |
| Delayed operations | `HashOperation`, `Schedule`, `ScheduleTargetAdmin`, `Cancel`, `GetSchedule`, `GetNonce` |
| Events | `RoleLabel`, `RoleGranted`, `RoleRevoked`, `RoleAdminChanged`, `RoleGuardianChanged`, `RoleGrantDelayChanged`, `TargetClosed`, `TargetAdminDelayUpdated`, `TargetFunctionRoleUpdated`, `OperationScheduled`, `OperationExecuted`, `OperationCanceled` |

The pure package defines the event schema, but the access realm emits events so
they are attributed to the realm that owns state.

## Intentional Gno Differences

- No instantiate message exists for Gno realms, so the access realm bootstraps
  `AdminRole` from `DefaultAdminAddress` during `init`.
- Union's `initial_authority` wiring is represented by the shared access realm
  and per-target selector configuration instead of each managed realm owning a
  nested authority instance.
- Generic manager-side execution remains intentionally different. Union executes
  encoded CosmWasm messages through the access manager; Gno stores and consumes
  scheduled operations, then the caller re-invokes the original target realm
  function with the same `dataHash`.
- ABI calldata selector extraction and execution-id stack tracking are not
  ported because Gno targets expose typed realm functions instead of encoded
  calldata.
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
