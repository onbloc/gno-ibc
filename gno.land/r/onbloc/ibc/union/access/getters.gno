package access

import manager "gno.land/p/onbloc/access/manager"

func HasRole(cur realm, role manager.RoleId, account address) manager.HasRoleResult {
	return accessState.HasRole(role, account)
}

func GetRoleAdmin(cur realm, role manager.RoleId) manager.RoleId {
	return accessState.GetRoleAdmin(role)
}

func GetRoleGrantDelay(cur realm, role manager.RoleId) manager.Delay {
	return accessState.GetRoleGrantDelay(role)
}

func GetFunctionRole(cur realm, selector manager.Selector) manager.RoleId {
	return GetTargetFunctionRole(cur, selector)
}

func GetTargetFunctionRole(cur realm, selector manager.Selector) manager.RoleId {
	target := cur.Previous().PkgPath()
	return accessState.GetTargetFunctionRole(target, selector)
}

func GetTargetAdminDelay(cur realm) manager.Delay {
	target := cur.Previous().PkgPath()
	return accessState.GetTargetAdminDelay(target)
}

func IsTargetClosed(cur realm) bool {
	target := cur.Previous().PkgPath()
	return accessState.IsTargetClosed(target)
}

func CanCall(cur realm, selector manager.Selector, caller address) manager.CanCallResult {
	target := cur.Previous().PkgPath()
	return accessState.CanCall(caller, target, selector)
}

func IsAuthorized(cur realm, selector manager.Selector, caller address) bool {
	target := cur.Previous().PkgPath()
	return accessState.IsAuthorized(caller, target, selector)
}

func CanAdminRole(cur realm, role manager.RoleId, caller address) manager.CanCallResult {
	return accessState.CanAdminRole(role, caller)
}

func CanManageTarget(cur realm, caller address) manager.CanCallResult {
	return accessState.CanManageTarget(caller)
}
