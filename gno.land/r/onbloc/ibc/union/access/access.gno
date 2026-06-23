package access

import "gno.land/p/onbloc/access/manager"

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
	selectorSetTargetClosed       manager.Selector = "set_target_closed"
	selectorSetTargetFunctionRole manager.Selector = "set_target_function_role"
)

func GrantRole(cur realm, role manager.RoleId, account address) bool {
	requireRoleAdmin(cur, role, selectorGrantRole)
	newMember := accessState.GrantRole(role, account)
	access := accessState.Roles[role].Members[account]
	emitRoleGrantedEvent(role, account, access.Since, newMember)
	return newMember
}

func RevokeRole(cur realm, role manager.RoleId, account address) bool {
	requireRoleAdmin(cur, role, selectorRevokeRole)
	revoked := accessState.RevokeRole(role, account)
	if revoked {
		emitRoleRevokedEvent(role, account)
	}
	return revoked
}

func RenounceRole(cur realm, role manager.RoleId, callerConfirmation address) bool {
	account := cur.Previous().Address()
	revoked := accessState.RenounceRole(role, account, callerConfirmation)
	if revoked {
		emitRoleRevokedEvent(role, account)
	}
	return revoked
}

func LabelRole(cur realm, role manager.RoleId, label string) {
	requireManagerAdmin(cur, selectorLabelRole)
	manager.RequireUnlockedConfigRole(role)
	emitRoleLabelEvent(role, label)
}

func SetRoleAdmin(cur realm, role manager.RoleId, admin manager.RoleId) {
	requireManagerAdmin(cur, selectorSetRoleAdmin)
	accessState.SetRoleAdmin(role, admin)
	emitRoleAdminChangedEvent(role, admin)
}

func SetGrantDelay(cur realm, role manager.RoleId, delay manager.Delay) {
	requireManagerAdmin(cur, selectorSetGrantDelay)
	accessState.SetGrantDelay(role, delay)
	emitRoleGrantDelayChangedEvent(role, delay, manager.CurrentTimepoint())
}

func SetFunctionRole(cur realm, selector manager.Selector, role manager.RoleId) {
	target := cur.Previous().PkgPath()
	requireManagerAdmin(cur, selectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRole(target, selector, role)
	emitTargetFunctionRoleUpdatedEvent(target, selector, role)
}

func SetFunctionRoles(cur realm, selectors []manager.Selector, role manager.RoleId) {
	target := cur.Previous().PkgPath()
	requireManagerAdmin(cur, selectorSetTargetFunctionRole)
	accessState.SetTargetFunctionRoles(target, selectors, role)
	for i := range selectors {
		emitTargetFunctionRoleUpdatedEvent(target, selectors[i], role)
	}
}

func SetTargetClosed(cur realm, closed bool) {
	target := cur.Previous().PkgPath()
	requireManagerAdmin(cur, selectorSetTargetClosed)
	accessState.SetTargetClosed(target, closed)
	emitTargetClosedEvent(target, closed)
}
