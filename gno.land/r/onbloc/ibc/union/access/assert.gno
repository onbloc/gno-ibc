package access

import manager "gno.land/p/onbloc/access/manager"

func AssertCanCall(cur realm, selector manager.Selector, caller address) {
	target := cur.Previous().PkgPath()
	if !accessState.IsAuthorized(caller, target, selector) {
		panic("caller not authorized to " + string(selector) + ": unauthorized")
	}
}

func requireManagerAdmin(cur realm, action manager.Selector) {
	if !accessState.CanManageTarget(cur.Previous().Address()).Immediate {
		panic("caller not authorized to " + string(action) + ": unauthorized")
	}
}

func requireRoleAdmin(cur realm, role manager.RoleId, action manager.Selector) {
	if !accessState.CanAdminRole(role, cur.Previous().Address()).Immediate {
		panic("caller not authorized to " + string(action) + ": unauthorized")
	}
}
