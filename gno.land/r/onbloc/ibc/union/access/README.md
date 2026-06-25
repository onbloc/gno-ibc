# Union Access Realm

Shared access authority for Union IBC realms.

This realm owns the `manager.State` from
`gno.land/p/onbloc/access/manager`. Core and app realms share this access
authority, while each managed realm remains a separate target keyed by its
package path.

Authorization guards use the non-crossing `AssertCanCall(0, cur, selector)` or
`AssertCanCallOrConsume(0, cur, selector, dataHash)` form. The caller passes its
current realm value, and access derives the target from `rlm.PkgPath()` and the
caller from `rlm.Previous().Address()`. Management functions are crossing calls;
per-target mutations derive the target from the previous realm package path.
Query getters are plain read surfaces that take the target path explicitly when
they inspect per-target configuration.

## References

- [Repository comparison guide](../../../../../../docs/spec-comparisons/access-management.md)
- OpenZeppelin Contracts:
  [`AccessManager` v5.6.1](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager)
- Union CosmWasm:
  [`access-manager`](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager),
  [`access-managed`](https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-managed)
- Union managed authority initialization:
  [core `access_managed_init_msg`](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L592-L604),
  [UCS03-ZKGM `access_managed_init_msg`](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/app/ucs03-zkgm/src/contract.rs#L67-L75)
- Union deployer:
  [role ids](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65-L68),
  [core relayer selector wiring](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1823-L1837),
  [UCS03-ZKGM role wiring](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1839-L1867),
  [role labels](https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1871-L1908)

## Bootstrap

Union passes `initial_admin` and `initial_authority` through instantiate or
migrate messages. Gno realms in this repository do not have that instantiate
message surface, so this realm bootstraps `AdminRole` from
`DefaultAdminAddress` in `init`.

The bootstrap also wires Union core relayer selectors to `RelayerRole` in
`deployer.gno`. This wiring is deployment policy, not an AccessManager default.

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

## Management Surface

- `GrantRole`
- `GrantRoleWithExecutionDelay`
- `RevokeRole`
- `RenounceRole`
- `LabelRole`
- `SetRoleAdmin`
- `SetRoleGuardian`
- `SetGrantDelay`
- `SetFunctionRole`
- `SetFunctionRoleDelayed`
- `SetFunctionRoles`
- `SetFunctionRolesDelayed`
- `SetTargetAdminDelay`
- `SetTargetAdminDelayDelayed`
- `SetTargetClosed`
- `SetTargetClosedDelayed`
- `Schedule`
- `ScheduleTargetAdmin`
- `Cancel`

This realm emits management events after successful state transitions. Event
type and attribute key constants live in the pure manager package, but emission
stays here so events are attributed to the state-owning realm.

## Authorization Surface

- `AssertCanCall`
- `AssertCanCallOrConsume`

`AssertCanCall` is intentionally non-crossing. Managed realms call it with
their own `cur realm`, so the asserted target is the managed realm itself. A
spoofed realm value is rejected with `ErrorSpoofedRealm`.

`AssertCanCallOrConsume` is the Gno-native delayed execution guard. If the
caller can execute immediately, it returns. If the caller is authorized only
with delay, it consumes the scheduled operation identified by caller, target,
selector, and `dataHash` before the managed realm continues its original
function body.

## Query Surface

- `AdminRole`
- `PublicRole`
- `Expiration`
- `MinSetback`
- `HasRole`
- `GetAccess`
- `GetRoleAdmin`
- `GetRoleGuardian`
- `GetRoleGrantDelay`
- `GetRoleLabel`
- `GetRoleLabels`
- `GetFunctionRole`
- `GetTargetFunctionRole`
- `GetTargetAdminDelay`
- `IsTargetClosed`
- `CanCall`
- `IsAuthorized`
- `CanAdminRole`
- `CanManageTarget`
- `CanManageTargetPath`
- `HashOperation`
- `GetSchedule`
- `GetNonce`

## Delayed Operations

This realm applies Union/OZ delay policy to Gno targets without a generic
manager-side executor:

- `GrantRoleWithExecutionDelay` stores account execution delay.
- Regranting an existing member updates its execution delay using Union/OZ
  delayed-value semantics; decreasing the delay remains pending until the
  required setback.
- `SetGrantDelay` and `SetTargetAdminDelay` use Union/OZ min-setback policy, so
  getters keep returning the current value until the new value's effect time.
- `Schedule` records delayed calls for target selectors when `CanCall` returns
  delayed authorization.
- `ScheduleTargetAdmin` records delayed target-configuration changes when
  `GetTargetAdminDelay(target)` is non-zero.
- `Cancel` accepts the original caller, `AdminRole`, or the required role's
  guardian.
- `Set*Delayed` management functions consume target-admin scheduled operations
  before applying the state transition.
- Managed realms use `AssertCanCallOrConsume` to consume delayed target
  operations from their original public entrypoints. If a previously scheduled
  operation exists and the caller later becomes immediate, the guard still
  consumes that ready schedule to match Union/OZ execution behavior.

The intentional runtime difference is generic execution. Union executes encoded
CosmWasm messages through the manager. Gno target realms must be invoked again
through the original function, passing the same `dataHash` to the access guard
so the scheduled operation can be consumed.
