package access

import manager "gno.land/p/onbloc/access/manager"

func AssertCanCall(cur realm, selector manager.Selector, caller address) {
	target := cur.Previous().PkgPath()
	if !accessState.IsAuthorized(caller, target, selector) {
		panic("caller not authorized to " + string(selector) + ": unauthorized")
	}
}
