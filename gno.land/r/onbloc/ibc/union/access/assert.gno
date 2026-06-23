package access

import "gno.land/p/onbloc/access/manager"

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
