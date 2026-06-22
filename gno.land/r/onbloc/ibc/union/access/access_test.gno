package access

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	manager "gno.land/p/onbloc/access/manager"
)

func TestGrantRoleDirectManagement(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer)
	if !HasRole(cur, RelayerRole, relayer) {
		t.Fatal("admin must be able to grant role through shared access")
	}

	RevokeRole(cross(cur), RelayerRole, relayer)
	if HasRole(cur, RelayerRole, relayer) {
		t.Fatal("admin must be able to revoke role through shared access")
	}
}

func TestGrantRoleRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	relayer := testutils.TestAddress("access-relayer")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, "caller not authorized to grant_role", func(cur realm) {
		GrantRole(cross(cur), RelayerRole, relayer)
	})
	if HasRole(cur, RelayerRole, relayer) {
		t.Fatal("rejected grant must not add the relayer")
	}
}

func TestSetFunctionRoleDirectManagement(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	if CanCall(cross(cur), "set_hook", caller) {
		t.Fatal("non-admin caller must not be authorized before role update")
	}

	SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)
	if !CanCall(cross(cur), "set_hook", caller) {
		t.Fatal("public role assignment must authorize arbitrary caller")
	}
}

func TestSetFunctionRoleRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, "caller not authorized to set_target_function_role", func(cur realm) {
		SetFunctionRole(cur, "set_hook", manager.PublicRole)
	})
	if GetFunctionRole(cross(cur), "set_hook") != manager.AdminRole {
		t.Fatal("rejected role update must not change selector role")
	}
}
