package zkgm

import (
	manager "gno.land/p/onbloc/access/manager"
	unionaccess "gno.land/r/onbloc/ibc/union/access"
)

var packagePath string

const (
	SelectorGrantRole             manager.Selector = "grant_role"
	SelectorRevokeRole            manager.Selector = "revoke_role"
	SelectorSetTargetFunctionRole manager.Selector = "set_target_function_role"
	SelectorUpdateImpl            manager.Selector = "update_impl"
	SelectorSetBucketConfig       manager.Selector = "set_bucket_config"
	SelectorSetRateLimitDisabled  manager.Selector = "set_rate_limit_disabled"
	SelectorPausable              manager.Selector = "pausable"
)

func init(cur realm) {
	packagePath = cur.PkgPath()
}

func GrantRole(_ int, rlm realm, role manager.RoleId, account address) {
	unionaccess.GrantRoleFromTarget(cross(rlm), packagePath, rlm.Previous().Address(), role, account)
}

func RevokeRole(_ int, rlm realm, role manager.RoleId, account address) {
	unionaccess.RevokeRoleFromTarget(cross(rlm), packagePath, rlm.Previous().Address(), role, account)
}

func SetFunctionRole(_ int, rlm realm, selector manager.Selector, role manager.RoleId) {
	unionaccess.SetFunctionRoleFromTarget(cross(rlm), packagePath, rlm.Previous().Address(), selector, role)
}

func GetFunctionRole(_ int, rlm realm, selector manager.Selector) manager.RoleId {
	return unionaccess.GetFunctionRole(cross(rlm), packagePath, selector)
}

func HasRole(_ int, rlm realm, role manager.RoleId, account address) bool {
	return unionaccess.HasRole(cross(rlm), role, account)
}

func CanCall(_ int, rlm realm, selector manager.Selector, caller address) bool {
	return unionaccess.CanCall(cross(rlm), packagePath, selector, caller)
}

func requireCanCall(_ int, rlm realm, selector manager.Selector) {
	if !unionaccess.CanCall(cross(rlm), packagePath, selector, rlm.Previous().Address()) {
		panic("caller not authorized to " + string(selector) + ": unauthorized")
	}
}
