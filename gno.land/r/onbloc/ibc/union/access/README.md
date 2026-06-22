# Union Access Realm

Shared access authority for Union IBC realms.

This realm owns the `manager.State` from
`gno.land/p/onbloc/access/manager`. Core and app realms call this shared realm
directly so the access realm can infer the managed target from
`cur.Previous().PkgPath()`.

## References

- OpenZeppelin Contracts `AccessManager` v5.6.1:
  https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.6.1/contracts/access/manager
- Union CosmWasm `access-manager`:
  https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager
- Union CosmWasm `access-managed`:
  https://github.com/unionlabs/union/tree/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-managed
- Union core initializes its managed authority from `access_managed_init_msg`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L592-L604
- Union UCS03-ZKGM initializes its managed authority from
  `access_managed_init_msg`:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/app/ucs03-zkgm/src/contract.rs#L67-L75
- Union deployer role ids:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65-L68
- Union deployer core relayer selector wiring:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1823-L1837
- Union deployer UCS03-ZKGM role wiring:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1839-L1867
- Union deployer role labels:
  https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1871-L1908

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
- `RevokeRole`
- `RenounceRole`
- `LabelRole`
- `SetRoleAdmin`
- `SetGrantDelay`
- `SetFunctionRole`
- `SetFunctionRoles`
- `SetTargetAdminDelay`
- `SetTargetClosed`

This realm emits management events after successful state transitions. Event
type and attribute key constants live in the pure manager package, but emission
stays here so events are attributed to the state-owning realm.

Guardian role configuration is intentionally not exposed yet because the
scheduling and cancellation surface is not implemented.
