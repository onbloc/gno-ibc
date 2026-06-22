package access

import manager "gno.land/p/onbloc/access/manager"

var accessState manager.State

// RelayerRole mirrors Union deployer's RELAYER role id.
// Reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65
const RelayerRole manager.RoleId = 1

const (
	selectorGrantRole             manager.Selector = "grant_role"
	selectorLabelRole             manager.Selector = "label_role"
	selectorRevokeRole            manager.Selector = "revoke_role"
	selectorSetTargetFunctionRole manager.Selector = "set_target_function_role"
)

func GrantRole(cur realm, role manager.RoleId, account address) {
	requireRoleAdmin(cur, role, selectorGrantRole)
	grantRoleUnchecked(role, account)
}

func RevokeRole(cur realm, role manager.RoleId, account address) {
	requireRoleAdmin(cur, role, selectorRevokeRole)
	revokeRoleUnchecked(role, account)
}

func LabelRole(cur realm, role manager.RoleId, label string) {
	requireManagerAdmin(cur, selectorLabelRole)
	accessState.LabelRole(role, label)
}

func SetFunctionRole(cur realm, selector manager.Selector, role manager.RoleId) {
	target := cur.Previous().PkgPath()
	requireManagerAdmin(cur, selectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRole(target, selector, role)
}

func SetFunctionRoles(cur realm, selectors []manager.Selector, role manager.RoleId) {
	target := cur.Previous().PkgPath()
	requireManagerAdmin(cur, selectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRoles(target, selectors, role)
}

func GetFunctionRole(cur realm, selector manager.Selector) manager.RoleId {
	target := cur.Previous().PkgPath()
	return accessState.GetTargetFunctionRole(target, selector)
}

func HasRole(cur realm, role manager.RoleId, account address) bool {
	return accessState.HasRole(role, account).IsMember
}

func CanCall(cur realm, selector manager.Selector, caller address) bool {
	target := cur.Previous().PkgPath()
	return accessState.IsAuthorized(caller, target, selector)
}

func grantRoleUnchecked(role manager.RoleId, account address) {
	accessState.GrantRole(role, account, 0)
}

func revokeRoleUnchecked(role manager.RoleId, account address) {
	accessState.RevokeRole(role, account)
}
