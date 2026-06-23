# Access Manager

Pure Gno port of the core permission model from OpenZeppelin Contracts
`AccessManager` v5.6.1.

Reference:

- OpenZeppelin Access Management concept guide:
  https://docs.openzeppelin.com/contracts/5.x/access-control#access-management
- OpenZeppelin Contracts `AccessManager` API reference:
  https://docs.openzeppelin.com/contracts/5.x/api/access#AccessManager
- OpenZeppelin Contracts `AccessManager` v5.6.1:
  https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager
- Union CosmWasm `access-manager`:
  https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager

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
- each role has an admin role, grant delay, and member access records;
- a member access record has an activation timePoint;
- current `TimePoint` is represented as Unix seconds in an `int64` wrapper and
  read from Gno block time with `time.Now().Unix()`;
- `CanCall` returns whether a call is immediately executable.

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
  https://docs.openzeppelin.com/contracts/5.x/access-control#access-management
- OpenZeppelin's API reference is useful for checking the public AccessManager
  surface and the fields intentionally not ported in this Gno package:
  https://docs.openzeppelin.com/contracts/5.x/api/access#AccessManager
- OpenZeppelin defines the target/function role model, admin role behavior,
  public role behavior, target closure, and delayed operation concepts:
  https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager
- Union's `access-manager` ports the OpenZeppelin manager to CosmWasm. Its init
  grants `ADMIN_ROLE` to `InitMsg.initial_admin`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/lib.rs#L135-L154

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

## Implemented API

Types:

- `RoleId`
- `Selector`
- `TimePoint`
- `Delay`
- `State`
- `RoleConfig`
- `Access`
- `TargetConfig`
- `CanCallResult`
- `HasRoleResult`

Constants:

- `AdminRole`
- `PublicRole`

Constructors:

- `NewRoleId`
- `NewSelector`
- `NewTimePoint`
- `NewDelay`
- `NewState`
- `NewRoleConfig`
- `NewAccess`
- `NewAccessWithDelay`
- `NewTargetConfig`
- `NewCanCallResult`
- `NewHasRoleResult`

Role helpers:

- `RoleId.Uint64`
- `RoleId.String`

Delay helpers:

- `Delay.Uint32`
- `Delay.String`

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
- `RevokeRole`
- `RenounceRole`
- `HasRole`

Role configuration:

- `SetRoleAdmin`
- `GetRoleAdmin`
- `SetGrantDelay`
- `GetRoleGrantDelay`
- `RequireUnlockedConfigRole`

Target configuration:

- `SetTargetFunctionRole`
- `SetTargetFunctionRoles`
- `GetTargetFunctionRole`
- `SetTargetClosed`
- `IsTargetClosed`

Authorization:

- `CanCall`
- `IsAuthorized`
- `CanAdminRole`
- `CanManageTarget`

Event schema:

- `RoleLabel`
- `RoleGranted`
- `RoleRevoked`
- `RoleAdminChanged`
- `RoleGrantDelayChanged`
- `TargetClosed`
- `TargetFunctionRoleUpdated`

## Not Implemented

This package intentionally does not implement OpenZeppelin's delayed operation
execution surface or the configuration that only becomes meaningful with it:

- `schedule`
- `execute`
- `cancel`
- `consumeScheduledOp`
- `hashOperation`
- operation nonce storage
- execution-id tracking
- account execution delay
- target admin delay
- ABI calldata selector extraction
- guardian role configuration

Those functions depend on EVM calldata, low-level target calls, operation hashes,
and execution context. In Gno, those concerns should be implemented by the
realm that owns the callable surface if delayed execution is needed.

`GrantDelay` is intentionally retained. It gates when a newly granted role
becomes active and does not require the delayed execution scheduler.

The pure package does not call `chain.Emit`. A consuming realm should emit the
currently implemented management events after the matching state transition
succeeds.
