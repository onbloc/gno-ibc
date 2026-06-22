package transfer

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	manager "gno.land/p/onbloc/access/manager"
)

func transferAdminForTest() address {
	// Unit package init has no previous deployer realm, so cur.Previous() is the empty address.
	return address("")
}

func resetAccess(cur realm, initialAdmin address) {
	testing.SetRealm(testing.NewUserRealm(address("")))
	GrantRole(0, cur, manager.AdminRole, initialAdmin)
	SetFunctionRole(0, cur, SelectorSetHook, manager.AdminRole)
	testing.SetRealm(testing.NewUserRealm(initialAdmin))
}

func TestAccessBootstrapsDeployOriginAdmin(cur realm, t *testing.T) {
	admin := transferAdminForTest()
	resetAccess(cur, admin)

	if !HasRole(0, cur, manager.AdminRole, admin) {
		t.Fatal("transfer access must grant ADMIN_ROLE to the deploy origin at bootstrap")
	}
	if !CanCall(0, cur, SelectorSetHook, admin) {
		t.Fatal("transfer admin must be authorized for unset function roles")
	}
}

func TestSetFunctionRoleCanOpenSetHook(cur realm, t *testing.T) {
	admin := transferAdminForTest()
	resetAccess(cur, admin)
	caller := address(testutils.TestAddress("transfer-caller"))

	if CanCall(0, cur, SelectorSetHook, caller) {
		t.Fatal("non-admin caller must not call SetHook before PUBLIC_ROLE assignment")
	}

	testing.SetRealm(testing.NewUserRealm(admin))
	SetFunctionRole(0, cur, SelectorSetHook, manager.PublicRole)

	if !CanCall(0, cur, SelectorSetHook, caller) {
		t.Fatal("PUBLIC_ROLE assignment must authorize any caller for SetHook")
	}
}

func TestTransferGrantRoleRejectsNonAdmin(cur realm, t *testing.T) {
	resetAccess(cur, transferAdminForTest())
	caller := address(testutils.TestAddress("transfer-caller"))

	testing.SetRealm(testing.NewUserRealm(caller))

	uassert.AbortsContains(t, cur, "caller not authorized to grant_role", func(cur realm) {
		GrantRole(0, cur, manager.NewRoleId(2), caller)
	})
}

func TestGrantAndRevokeAdminRoleUpdatesTransferRights(cur realm, t *testing.T) {
	oldAdmin := transferAdminForTest()
	newAdmin := address(testutils.TestAddress("transfer-new-admin"))
	resetAccess(cur, oldAdmin)

	testing.SetRealm(testing.NewUserRealm(oldAdmin))
	GrantRole(0, cur, manager.AdminRole, newAdmin)

	if !HasRole(0, cur, manager.AdminRole, oldAdmin) {
		t.Fatal("GrantRole must keep ADMIN_ROLE for the old admin")
	}
	if !HasRole(0, cur, manager.AdminRole, newAdmin) {
		t.Fatal("GrantRole must grant ADMIN_ROLE to the new admin")
	}
	if !CanCall(0, cur, SelectorSetHook, newAdmin) {
		t.Fatal("new admin must gain default-admin selector access")
	}

	RevokeRole(0, cur, manager.AdminRole, newAdmin)

	if HasRole(0, cur, manager.AdminRole, newAdmin) {
		t.Fatal("RevokeRole must revoke ADMIN_ROLE from the new admin")
	}
	if CanCall(0, cur, SelectorSetHook, newAdmin) {
		t.Fatal("revoked admin must lose default-admin selector access")
	}
}

func TestGrantAdminRoleRejectsTransferNonAdmin(cur realm, t *testing.T) {
	oldAdmin := transferAdminForTest()
	newAdmin := address(testutils.TestAddress("transfer-new-admin"))
	caller := address(testutils.TestAddress("transfer-non-admin"))
	resetAccess(cur, oldAdmin)

	testing.SetRealm(testing.NewUserRealm(caller))

	uassert.AbortsContains(t, cur, "caller not authorized to grant_role", func(cur realm) {
		GrantRole(0, cur, manager.AdminRole, newAdmin)
	})
	if !HasRole(0, cur, manager.AdminRole, oldAdmin) {
		t.Fatal("rejected grant must keep the old admin")
	}
	if HasRole(0, cur, manager.AdminRole, newAdmin) {
		t.Fatal("rejected grant must not add the new admin")
	}
}
