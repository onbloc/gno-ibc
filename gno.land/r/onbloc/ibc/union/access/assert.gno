package access

import "gno.land/p/onbloc/access/manager"

// AssertCanCall panics unless caller can call selector on the calling realm's target path.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-managed/src/restricted.rs#L38-L66
func AssertCanCall(cur realm, selector manager.Selector, caller address) {
	target := cur.Previous().PkgPath()
	if !accessState.IsAuthorized(caller, target, selector) {
		panic(AccessManagerUnauthorizedCallError(caller, target, selector))
	}
}

func requireManagerAdmin(cur realm, _ manager.Selector) {
	caller := cur.Previous().Address()
	if !accessState.CanManageTarget(caller).Immediate {
		panic(AccessManagerUnauthorizedAccountError(caller, manager.AdminRole))
	}
}

func requireRoleAdmin(cur realm, role manager.RoleId, _ manager.Selector) {
	caller := cur.Previous().Address()
	if !accessState.CanAdminRole(role, caller).Immediate {
		panic(AccessManagerUnauthorizedAccountError(caller, accessState.GetRoleAdmin(role)))
	}
}
