# Access Manager

Pure Gno port of the core permission model from OpenZeppelin Contracts
`AccessManager` v5.6.1.

Reference:

- Repository comparison guide:
  [docs/spec-comparisons/access-management.md](../../../../../docs/spec-comparisons/access-management.md)
- OpenZeppelin Access Management concept guide:
  [Access Management](https://docs.openzeppelin.com/contracts/5.x/access-control#access-management)
- OpenZeppelin Contracts `AccessManager` API reference:
  [`AccessManager` API](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessManager)
- OpenZeppelin Contracts `AccessManager` v5.6.1:
  [`contracts/access/manager`](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager)
- Union CosmWasm `access-manager`:
  [`cosmwasm/access-manager`](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager)

This package is a state transition library, not a realm. It does not own
storage, inspect `cur realm`, or decide who the caller is. A realm that wants
AccessManager behavior should store a `manager.State`, pass the caller address,
target identifier, and selector into `State` methods, and expose any public
management API it needs.

## Model

The model follows OpenZeppelin's `AccessManager` shape:

- roles are `uint64` identifiers;
- `AdminRole` is `0`;
- `PublicRole` is `uint64 max` and every account is always a member;
- permissions are scoped by target and selector;
- an unset target function role defaults to `AdminRole`;
- a target can be closed, rejecting calls even when the function is public;
- each role has an admin role, guardian role, grant delay, and member access
  records;
- a member access record has an activation timePoint and execution delay;
- role grant delay, target admin delay, and member execution-delay reductions
  use Union/OZ delayed-value update semantics instead of changing immediately;
- role labels are stored for discoverability queries and emitted as events by
  the consuming realm;
- delayed operations are keyed by caller, target, selector, and `dataHash`;
- target administration can require a target-specific admin delay;
- current `TimePoint` is represented as Unix seconds in an `int64` wrapper and
  read from Gno block time with `time.Now().Unix()`;
- `CanCall` returns whether a call is immediate, delayed, or unauthorized.

Role labels follow OpenZeppelin's event-only model from the pure package's
perspective: labels are not stored in `State`. This package only defines the
Union/OZ event type and attribute names plus role-lock validation; the consuming
realm must emit `RoleLabel` so the event is attributed to the state-owning
realm.

## Reference Map

Use these references when checking whether this package and the consuming realms
are still aligned with the source models:

- OpenZeppelin's access-management guide describes the shared manager model:
  roles are granted to accounts, target functions are assigned to roles, and a
  caller is authorized when it has the role assigned to the target function:
  [Access Management](https://docs.openzeppelin.com/contracts/5.x/access-control#access-management)
- OpenZeppelin's API reference is useful for checking the public AccessManager
  surface and the fields adapted to the Gno-native execution model:
  [`AccessManager` API](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessManager)
- OpenZeppelin defines the target/function role model, admin role behavior,
  public role behavior, target closure, and delayed operation concepts:
  [`AccessManager` source](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager)
- Union's `access-manager` ports the OpenZeppelin manager to CosmWasm. Its init
  grants `ADMIN_ROLE` to `InitMsg.initial_admin`:
  [`init` authority grant](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/lib.rs#L135-L154)

## Usage

Store `State` in the consuming realm and initialize it with `NewState` during
bootstrap. Methods also lazily initialize internal maps, but `NewState` is the
clearest construction path.

```go
var accessState manager.State

func init(cur realm) {
	accessState = manager.NewState()
	accessState.GrantRole(manager.AdminRole, cur.Previous().Address())
}
```

Configure target functions by package path or any other stable target string.
Production selector-role wiring is deployer policy, not an AccessManager
default.

```go
const ProtectedTarget = "gno.land/r/example/protected"
const OperatorRole manager.RoleId = 1
const SelectorProtected manager.Selector = "protected"

func configureAccess() {
	accessState.SetTargetFunctionRole(ProtectedTarget, SelectorProtected, OperatorRole)
}
```

Check access by passing the caller address, target identifier, and selector.

```go
func Protected(cur realm) {
	if !accessState.IsAuthorized(cur.Previous().Address(), ProtectedTarget, SelectorProtected) {
		panic("unauthorized")
	}
	// protected logic
}
```

The consuming realm is responsible for checking whether the caller can mutate
the manager state. `GrantRole` only applies the state transition; it does not
inspect `cur realm`.

Delayed operations use explicit operation data instead of EVM or CosmWasm
calldata. Callers provide a stable `dataHash` for the target operation, schedule
the operation with `Schedule` or `ScheduleTargetAdmin`, and the consuming realm
later calls `ConsumeScheduledOp` after re-entering the original protected
surface.

## Implemented API

Types:

- `RoleId`
- `Selector`
- `TimePoint`
- `Delay`
- `DelayedValue`
- `State`
- `RoleConfig`
- `Access`
- `TargetConfig`
- `CanCallResult`
- `HasRoleResult`
- `FullAccess`
- `RoleLabel`
- `OperationId`
- `Nonce`
- `Schedule`

Constants:

- `AdminRole`
- `PublicRole`
- `MinSetback`

Constructors:

- `NewRoleId`
- `NewSelector`
- `NewTimePoint`
- `NewDelay`
- `NewDelayedValue`
- `NewState`
- `NewRoleConfig`
- `NewAccess`
- `NewTargetConfig`
- `NewCanCallResult`
- `NewHasRoleResult`
- `NewSchedule`

Role helpers:

- `RoleId.Uint64`
- `RoleId.String`

Delay helpers:

- `Delay.Uint32`
- `Delay.String`
- `DelayedValue.Get`
- `DelayedValue.GetFull`
- `DelayedValue.WithUpdate`

TimePoint helpers:

- `CurrentTimePoint`
- `TimePoint.After`
- `TimePoint.Before`
- `TimePoint.Equal`
- `TimePoint.String`
- `TimePoint.Int64`
- `TimePoint.IsZero`

Role membership:

- `GrantRole`
- `GrantRoleWithExecutionDelay`
- `RevokeRole`
- `RenounceRole`
- `HasRole`
- `GetAccess`

Role configuration:

- `LabelRole`
- `GetRoleLabel`
- `GetRoleLabels`
- `SetRoleAdmin`
- `GetRoleAdmin`
- `SetRoleGuardian`
- `GetRoleGuardian`
- `SetGrantDelay`
- `GetRoleGrantDelay`
- `RequireUnlockedConfigRole`

Target configuration:

- `SetTargetFunctionRole`
- `SetTargetFunctionRoles`
- `GetTargetFunctionRole`
- `SetTargetAdminDelay`
- `GetTargetAdminDelay`
- `SetTargetClosed`
- `IsTargetClosed`

Authorization:

- `CanCall`
- `IsAuthorized`
- `CanAdminRole`
- `CanManageTarget`
- `CanManageTargetPath`

Delayed operations:

- `HashOperation`
- `GetSchedule`
- `GetNonce`
- `Schedule`
- `ScheduleTargetAdmin`
- `Cancel`
- `ConsumeScheduledOp`

Event schema:

- `RoleLabel`
- `RoleGranted`
- `RoleRevoked`
- `RoleAdminChanged`
- `RoleGuardianChanged`
- `RoleGrantDelayChanged`
- `TargetClosed`
- `TargetAdminDelayUpdated`
- `TargetFunctionRoleUpdated`
- `OperationScheduled`
- `OperationExecuted`
- `OperationCanceled`

## Gno Delayed Operation Model

The package implements Union/OZ delay policy but not generic low-level target
dispatch. Gno has no EVM-style calldata selector extraction and this pure
package cannot call arbitrary target realms. Instead, delayed operations are
authorized and stored here, then consumed by the realm that owns the callable
surface.

- `GrantDelay` gates when a newly granted role becomes active.
- `GrantRoleWithExecutionDelay` stores an execution delay for an active member.
- `CanCall` returns immediate authorization only when the member has no
  execution delay. Delayed members receive `Authorized=true`, `Immediate=false`,
  and the required `Delay`.
- `Schedule` stores delayed target operations for callers that are authorized
  only with delay.
- `ScheduleTargetAdmin` stores delayed target-configuration operations when a
  target admin delay applies.
- `ConsumeScheduledOp` clears a ready, unexpired operation.
- `Cancel` can be called by the original caller, `AdminRole`, or the guardian
  role configured for the target selector's required role.

The remaining intentional difference is generic execution: OpenZeppelin and
Union execute encoded target messages through the manager, while Gno target
realms must be called again through their original public surface and consume
the scheduled operation from that guard.

The pure package does not call `chain.Emit`. A consuming realm should emit the
currently implemented management events after the matching state transition
succeeds.
