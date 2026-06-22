package zkgm

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	manager "gno.land/p/onbloc/access/manager"
)

func TestAccessBootstrapsDeployOriginAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	admin := zkgmAdminForTest()

	if !HasRole(0, cur, manager.AdminRole, admin) {
		t.Fatal("zkgm access must grant ADMIN_ROLE to the deploy origin at bootstrap")
	}
	if !CanCall(0, cur, SelectorUpdateImpl, admin) {
		t.Fatal("zkgm admin must be authorized for unset function roles")
	}
}

func TestSetFunctionRoleCanOpenPausable(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	caller := address(testutils.TestAddress("zkgm-caller"))

	if CanCall(0, cur, SelectorPausable, caller) {
		t.Fatal("non-admin caller must not call Pausable before PUBLIC_ROLE assignment")
	}

	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	SetFunctionRole(0, cur, SelectorPausable, manager.PublicRole)

	testing.SetRealm(testing.NewUserRealm(caller))
	Pausable(cross(cur), true)

	if !paused {
		t.Fatal("PUBLIC_ROLE assignment must authorize any caller for Pausable")
	}
}

func TestZkgmGrantRoleRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	caller := address(testutils.TestAddress("zkgm-caller"))

	testing.SetRealm(testing.NewUserRealm(caller))

	uassert.AbortsContains(t, cur, "caller not authorized to grant_role", func(cur realm) {
		GrantRole(0, cur, manager.NewRoleId(2), caller)
	})
}

func TestGrantAndRevokeAdminRoleUpdatesZkgmRights(cur realm, t *testing.T) {
	oldAdmin := zkgmAdminForTest()
	newAdmin := address(testutils.TestAddress("zkgm-new-admin"))
	resetZkgmForTest(cur)

	testing.SetRealm(testing.NewUserRealm(oldAdmin))
	GrantRole(0, cur, manager.AdminRole, newAdmin)

	if !HasRole(0, cur, manager.AdminRole, oldAdmin) {
		t.Fatal("GrantRole must keep ADMIN_ROLE for the old admin")
	}
	if !HasRole(0, cur, manager.AdminRole, newAdmin) {
		t.Fatal("GrantRole must grant ADMIN_ROLE to the new admin")
	}
	if !CanCall(0, cur, SelectorPausable, newAdmin) {
		t.Fatal("new admin must gain default-admin selector access")
	}

	RevokeRole(0, cur, manager.AdminRole, newAdmin)

	if HasRole(0, cur, manager.AdminRole, newAdmin) {
		t.Fatal("RevokeRole must revoke ADMIN_ROLE from the new admin")
	}
	if CanCall(0, cur, SelectorPausable, newAdmin) {
		t.Fatal("revoked admin must lose default-admin selector access")
	}
}

func TestGrantAdminRoleRejectsZkgmNonAdmin(cur realm, t *testing.T) {
	oldAdmin := zkgmAdminForTest()
	newAdmin := address(testutils.TestAddress("zkgm-new-admin"))
	caller := address(testutils.TestAddress("zkgm-non-admin"))
	resetZkgmForTest(cur)

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
