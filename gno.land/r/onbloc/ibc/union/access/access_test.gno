package access

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	manager "gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
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

func TestLabelRoleRequiresManagerAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	LabelRole(cross(cur), RelayerRole, "RELAYER")

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, "caller not authorized to label_role", func(cur realm) {
		LabelRole(cross(cur), RelayerRole, "RELAYER")
	})
}

func TestUnionDeployerRelayerSelectorSetup(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	ResetForTest(cur, admin)

	if HasRole(cur, RelayerRole, admin) {
		t.Fatal("initial admin must not receive relayer role during access-manager bootstrap")
	}
	for _, selector := range types.RelayerSelectors() {
		if accessState.GetTargetFunctionRole(CoreRealmPath, selector) != RelayerRole {
			t.Fatalf("%s must be initialized with relayer role", selector)
		}
	}
	if accessState.GetTargetFunctionRole(CoreRealmPath, "grant_role") != manager.AdminRole {
		t.Fatal("grant_role must not be initialized with relayer role")
	}
	if accessState.GetTargetFunctionRole(CoreRealmPath, "revoke_role") != manager.AdminRole {
		t.Fatal("revoke_role must not be initialized with relayer role")
	}
}
