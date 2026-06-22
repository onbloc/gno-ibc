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
	GrantRole(cross(cur), RelayerRole, relayer, 0)
	if !HasRole(cur, RelayerRole, relayer).IsMember {
		t.Fatal("admin must be able to grant role through shared access")
	}

	RevokeRole(cross(cur), RelayerRole, relayer)
	if HasRole(cur, RelayerRole, relayer).IsMember {
		t.Fatal("admin must be able to revoke role through shared access")
	}
}

func TestGrantRoleRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	relayer := testutils.TestAddress("access-relayer")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, ErrorAccessManagerUnauthorizedAccount, func(cur realm) {
		GrantRole(cross(cur), RelayerRole, relayer, 0)
	})
	if HasRole(cur, RelayerRole, relayer).IsMember {
		t.Fatal("rejected grant must not add the relayer")
	}
}

func TestSetFunctionRoleDirectManagement(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	if CanCall(cross(cur), "set_hook", caller).Immediate {
		t.Fatal("non-admin caller must not be authorized before role update")
	}

	SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)
	if !CanCall(cross(cur), "set_hook", caller).Immediate {
		t.Fatal("public role assignment must authorize arbitrary caller")
	}
}

func TestSetFunctionRoleRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, ErrorAccessManagerUnauthorizedAccount, func(cur realm) {
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
	uassert.AbortsContains(t, cur, ErrorAccessManagerUnauthorizedAccount, func(cur realm) {
		LabelRole(cross(cur), RelayerRole, "RELAYER")
	})
}

func TestRoleConfigurationSurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	roleAdmin := testutils.TestAddress("access-role-admin")
	relayer := testutils.TestAddress("access-relayer")
	const roleAdminRole manager.RoleId = 7
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), roleAdminRole, roleAdmin, 0)
	SetRoleAdmin(cross(cur), RelayerRole, roleAdminRole)
	SetRoleGuardian(cross(cur), RelayerRole, roleAdminRole)
	SetGrantDelay(cross(cur), RelayerRole, 5)

	if GetRoleAdmin(cur, RelayerRole) != roleAdminRole {
		t.Fatal("SetRoleAdmin must update role admin")
	}
	if GetRoleGuardian(cur, RelayerRole) != roleAdminRole {
		t.Fatal("SetRoleGuardian must update role guardian")
	}
	if GetRoleGrantDelay(cur, RelayerRole) != 5 {
		t.Fatal("SetGrantDelay must update role grant delay")
	}
	if !CanAdminRole(cur, RelayerRole, roleAdmin).Immediate {
		t.Fatal("role admin member must be able to administer relayer role")
	}

	SetGrantDelay(cross(cur), RelayerRole, 0)
	testing.SetRealm(testing.NewUserRealm(roleAdmin))
	GrantRole(cross(cur), RelayerRole, relayer, 3)
	membership := HasRole(cur, RelayerRole, relayer)
	if !membership.IsMember {
		t.Fatal("GrantRole must add active relayer when grant delay is zero")
	}
	if membership.ExecutionDelay != 3 {
		t.Fatal("GrantRole must store execution delay")
	}
}

func TestRenounceRoleSurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer, 0)

	testing.SetRealm(testing.NewUserRealm(relayer))
	uassert.AbortsContains(t, cur, manager.ErrorAccessManagerBadConfirmation, func(cur realm) {
		RenounceRole(cross(cur), RelayerRole, admin)
	})
	RenounceRole(cross(cur), RelayerRole, relayer)
	if HasRole(cur, RelayerRole, relayer).IsMember {
		t.Fatal("RenounceRole must revoke caller membership")
	}
}

func TestTargetConfigurationSurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)
	SetTargetAdminDelay(cross(cur), 9)

	if GetTargetFunctionRole(cross(cur), "set_hook") != manager.PublicRole {
		t.Fatal("SetFunctionRole must update inferred target selector role")
	}
	if GetTargetAdminDelay(cross(cur)) != 9 {
		t.Fatal("SetTargetAdminDelay must update inferred target delay")
	}
	if !CanManageTarget(cur, admin).Immediate {
		t.Fatal("admin role member must be able to manage targets")
	}
	if !IsAuthorized(cross(cur), "set_hook", caller) {
		t.Fatal("public selector must authorize arbitrary caller")
	}

	SetTargetClosed(cross(cur), true)
	if !IsTargetClosed(cross(cur)) {
		t.Fatal("SetTargetClosed must close inferred target")
	}
	if CanCall(cross(cur), "set_hook", caller).Immediate {
		t.Fatal("closed target must reject authorized caller")
	}

	SetTargetClosed(cross(cur), false)
	if !CanCall(cross(cur), "set_hook", caller).Immediate {
		t.Fatal("reopened target must restore selector authorization")
	}
}

func TestUnionDeployerRelayerSelectorSetup(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	ResetForTest(cur, admin)

	if HasRole(cur, RelayerRole, admin).IsMember {
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
