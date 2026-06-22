# Access Manager

Pure Gno port of the core permission model from OpenZeppelin Contracts
`AccessManager` v5.6.1.

Reference:

- OpenZeppelin Contracts `AccessManager` v5.6.1:
  https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager
- Union CosmWasm `access-manager`:
  https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager
- Union CosmWasm `access-managed`:
  https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-managed

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
- a member access record has an activation timepoint and execution delay;
- current timepoint is read from Gno block time with `time.Now().Unix()`;
- `CanCall` returns whether a call is immediately executable and the delay if it
  is not immediate.

`LabelRole` follows OpenZeppelin's event-only model: labels are emitted as
`RoleLabel` events and are not stored in `State`.

## Reference Map

Use these references when checking whether this package and the consuming realms
are still aligned with the source models:

- OpenZeppelin defines the target/function role model, admin role behavior,
  public role behavior, target closure, and delayed operation concepts:
  https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager
- Union's `access-manager` ports the OpenZeppelin manager to CosmWasm. Its init
  grants `ADMIN_ROLE` to `InitMsg.initial_admin`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/lib.rs#L135-L154
- Union's `access-managed` stores `InitMsg.initial_authority` on each managed
  contract and routes restricted calls through that authority:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-managed/src/lib.rs#L57-L69
- Union core initializes its managed authority from `access_managed_init_msg`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L592-L604
- Union UCS03-ZKGM initializes its managed authority from
  `access_managed_init_msg`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/app/ucs03-zkgm/src/contract.rs#L67-L75
- Union deployer defines role ids used by production wiring:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65-L68
- Union deployer assigns core relayer selectors to `RELAYER`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1823-L1837
- Union deployer assigns UCS03-ZKGM rate-limit selectors to `RATE_LIMITER` and
  selected UCS03-ZKGM selectors to `PUBLIC_ROLE`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1839-L1867
- Union deployer labels `RELAYER`, `PAUSER`, `UNPAUSER`, and `RATE_LIMITER`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1871-L1908

## Usage

Store `State` in the consuming realm and initialize it with `NewState` during
bootstrap. Methods also lazily initialize internal maps, but `NewState` is the
clearest construction path.

In this repository, the shared Union access realm
`gno.land/r/onbloc/ibc/union/access` owns the single `manager.State`. Core and
app realms keep thin wrappers that route through that shared realm with their
package path as the target. This mirrors Union's AccessManager plus
AccessManaged split: the manager owns role/selector state, and managed
contracts pass their own target identity when checking calls.

Union passes `initial_admin` and `initial_authority` through instantiate or
migrate messages. Gno realms in this repository do not have that instantiate
message surface, so the shared access realm bootstraps `AdminRole` from
`cur.Previous().Address()` in `init`.

```go
var accessState manager.State

func init(cur realm) {
	accessState = manager.NewState()
	accessState.GrantRole(manager.AdminRole, cur.Previous().Address(), 0)
}
```

Configure target functions by package path or any other stable target string.
Union's production selector-role wiring is deployer policy, not an
AccessManager default. In this repository, the shared access realm keeps the
current bootstrap equivalent in `deployer.gno`.

```go
const RelayerRole manager.RoleId = 1
const SelectorPacketRecv manager.Selector = "packet_recv"

func configureCoreAccess(target string) {
	accessState.SetTargetFunctionRole(target, SelectorPacketRecv, RelayerRole)
}
```

Check access from the realm using the caller address extracted from the correct
frame, usually `cur.Previous().Address()` for externally invoked realm methods.

```go
func requireCanCall(cur realm, target string, selector manager.Selector) {
	caller := cur.Previous().Address()
	if !accessState.IsAuthorized(caller, target, selector) {
		panic("unauthorized")
	}
}
```

Management wrappers should enforce the same authorization rules as the caller
realm wants to expose. For example, `GrantRole` should normally require
`state.CanAdminRole(role, caller)`, while target function role changes should
normally require `state.CanManageTarget(caller)`.

## Implemented API

Types:

- `RoleId`
- `Selector`
- `Timepoint`
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
- `NewTimepoint`
- `NewDelay`
- `NewState`
- `NewRoleConfig`
- `NewAccess`
- `NewTargetConfig`
- `NewCanCallResult`
- `NewHasRoleResult`

Timepoint helpers:

- `CurrentTimepoint`

Role membership:

- `GrantRole`
- `RevokeRole`
- `RenounceRole`
- `HasRole`

Role configuration:

- `SetRoleAdmin`
- `GetRoleAdmin`
- `SetRoleGuardian`
- `GetRoleGuardian`
- `SetGrantDelay`
- `GetRoleGrantDelay`
- `LabelRole`

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

Events:

- `RoleLabel`

## Union Role Coverage

Currently adopted role ids:

- `AdminRole = 0`
- Core `RelayerRole = 1`, matching Union deployer's `RELAYER`
- `PublicRole = uint64 max`

Known Union deployer roles not ported yet:

- `PAUSER = 2`
- `UNPAUSER = 3`
- `RATE_LIMITER = 4`

Those should be added only when the consuming realms expose the matching
selector groups and tests.

## Not Implemented

This package intentionally does not implement OpenZeppelin's delayed operation
execution surface:

- `schedule`
- `execute`
- `cancel`
- `consumeScheduledOp`
- `hashOperation`
- operation nonce storage
- execution-id tracking
- ABI calldata selector extraction

Those functions depend on EVM calldata, low-level target calls, operation hashes,
and execution context. In Gno, those concerns should be implemented by the
realm that owns the callable surface if delayed execution is needed.

The rest of OpenZeppelin's management events are not emitted yet. They should be
added alongside the matching state transitions as the port expands.
