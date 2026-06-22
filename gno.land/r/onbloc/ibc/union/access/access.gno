package access

import manager "gno.land/p/onbloc/access/manager"

var accessState manager.State

// RelayerRole mirrors Union deployer's RELAYER role id.
// Reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65
const RelayerRole manager.RoleId = 1

const (
	CoreTarget     = "gno.land/r/onbloc/ibc/union/core"
	TransferTarget = "gno.land/r/onbloc/ibc/union/apps/transfer"
	ZkgmTarget     = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func GrantRole(cur realm, role manager.RoleId, account address) {
	requireRoleAdmin(cur, role, SelectorGrantRole)
	grantRoleUnchecked(role, account)
}

func GrantRoleFromTarget(cur realm, target string, caller address, role manager.RoleId, account address) {
	requireTargetCaller(cur, target, SelectorGrantRole)
	requireRoleAdminForCaller(caller, role, SelectorGrantRole)
	grantRoleUnchecked(role, account)
}

func RevokeRole(cur realm, role manager.RoleId, account address) {
	requireRoleAdmin(cur, role, SelectorRevokeRole)
	revokeRoleUnchecked(role, account)
}

func RevokeRoleFromTarget(cur realm, target string, caller address, role manager.RoleId, account address) {
	requireTargetCaller(cur, target, SelectorRevokeRole)
	requireRoleAdminForCaller(caller, role, SelectorRevokeRole)
	revokeRoleUnchecked(role, account)
}

func SetFunctionRole(cur realm, target string, selector manager.Selector, role manager.RoleId) {
	requireManagerAdmin(cur, SelectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRole(target, selector, role)
}

func SetFunctionRoleFromTarget(cur realm, target string, caller address, selector manager.Selector, role manager.RoleId) {
	requireTargetCaller(cur, target, SelectorSetTargetFunctionRole)
	requireManagerAdminForCaller(caller, SelectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRole(target, selector, role)
}

func SetFunctionRoles(cur realm, target string, selectors []manager.Selector, role manager.RoleId) {
	requireManagerAdmin(cur, SelectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRoles(target, selectors, role)
}

func SetFunctionRolesFromTarget(cur realm, target string, caller address, selectors []manager.Selector, role manager.RoleId) {
	requireTargetCaller(cur, target, SelectorSetTargetFunctionRole)
	requireManagerAdminForCaller(caller, SelectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRoles(target, selectors, role)
}

func GetFunctionRole(cur realm, target string, selector manager.Selector) manager.RoleId {
	return accessState.GetTargetFunctionRole(target, selector)
}

func HasRole(cur realm, role manager.RoleId, account address) bool {
	return accessState.HasRole(role, account).IsMember
}

func CanCall(cur realm, target string, selector manager.Selector, caller address) bool {
	return accessState.IsAuthorized(caller, target, selector)
}

func requireManagerAdmin(cur realm, action manager.Selector) {
	requireManagerAdminForCaller(cur.Previous().Address(), action)
}

func requireManagerAdminForCaller(caller address, action manager.Selector) {
	if !accessState.CanManageTarget(caller).Immediate {
		panic("caller not authorized to " + string(action) + ": unauthorized")
	}
}

func requireRoleAdmin(cur realm, role manager.RoleId, action manager.Selector) {
	requireRoleAdminForCaller(cur.Previous().Address(), role, action)
}

func requireRoleAdminForCaller(caller address, role manager.RoleId, action manager.Selector) {
	if !accessState.CanAdminRole(role, caller).Immediate {
		panic("caller not authorized to " + string(action) + ": unauthorized")
	}
}

func requireTargetCaller(cur realm, target string, action manager.Selector) {
	if cur.Previous().PkgPath() != target {
		panic("caller not authorized to " + string(action) + ": unauthorized")
	}
}

func grantRoleUnchecked(role manager.RoleId, account address) {
	accessState.GrantRole(role, account, 0)
}

func revokeRoleUnchecked(role manager.RoleId, account address) {
	accessState.RevokeRole(role, account)
}
