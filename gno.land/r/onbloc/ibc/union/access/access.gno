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
	selectorSetGrantDelay         manager.Selector = "set_grant_delay"
	selectorSetRoleAdmin          manager.Selector = "set_role_admin"
	selectorSetRoleGuardian       manager.Selector = "set_role_guardian"
	selectorSetTargetAdminDelay   manager.Selector = "set_target_admin_delay"
	selectorSetTargetClosed       manager.Selector = "set_target_closed"
	selectorSetTargetFunctionRole manager.Selector = "set_target_function_role"
)

func GrantRole(cur realm, role manager.RoleId, account address, executionDelay manager.Delay) bool {
	requireRoleAdmin(cur, role, selectorGrantRole)
	return accessState.GrantRole(role, account, executionDelay)
}

func RevokeRole(cur realm, role manager.RoleId, account address) bool {
	requireRoleAdmin(cur, role, selectorRevokeRole)
	return accessState.RevokeRole(role, account)
}

func RenounceRole(cur realm, role manager.RoleId, callerConfirmation address) bool {
	return accessState.RenounceRole(role, cur.Previous().Address(), callerConfirmation)
}

func LabelRole(cur realm, role manager.RoleId, label string) {
	requireManagerAdmin(cur, selectorLabelRole)
	accessState.LabelRole(role, label)
}

func SetRoleAdmin(cur realm, role manager.RoleId, admin manager.RoleId) {
	requireManagerAdmin(cur, selectorSetRoleAdmin)
	accessState.SetRoleAdmin(role, admin)
}

func SetRoleGuardian(cur realm, role manager.RoleId, guardian manager.RoleId) {
	requireManagerAdmin(cur, selectorSetRoleGuardian)
	accessState.SetRoleGuardian(role, guardian)
}

func SetGrantDelay(cur realm, role manager.RoleId, delay manager.Delay) {
	requireManagerAdmin(cur, selectorSetGrantDelay)
	accessState.SetGrantDelay(role, delay)
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

func SetTargetAdminDelay(cur realm, delay manager.Delay) {
	target := cur.Previous().PkgPath()
	requireManagerAdmin(cur, selectorSetTargetAdminDelay)
	accessState.SetTargetAdminDelay(target, delay)
}

func SetTargetClosed(cur realm, closed bool) {
	target := cur.Previous().PkgPath()
	requireManagerAdmin(cur, selectorSetTargetClosed)
	accessState.SetTargetClosed(target, closed)
}
