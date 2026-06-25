package access

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestGrantRoleDirectManagement(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer)
	if !HasRole(RelayerRole, relayer).IsMember {
		t.Fatal("admin must be able to grant role through shared access")
	}

	RevokeRole(cross(cur), RelayerRole, relayer)
	if HasRole(RelayerRole, relayer).IsMember {
		t.Fatal("admin must be able to revoke role through shared access")
	}
}

func TestGrantRoleRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	relayer := testutils.TestAddress("access-relayer")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, ErrAccessManagerUnauthorizedAccount, func(cur realm) {
		GrantRole(cross(cur), RelayerRole, relayer)
	})
	if HasRole(RelayerRole, relayer).IsMember {
		t.Fatal("rejected grant must not add the relayer")
	}
}

func TestRoleMembershipRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	relayer := testutils.TestAddress("access-relayer")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer)

	tests := []struct {
		name string
		run  func(cur realm)
	}{
		{
			name: "grant",
			run: func(cur realm) {
				GrantRole(cross(cur), RelayerRole, caller)
			},
		},
		{
			name: "revoke",
			run: func(cur realm) {
				RevokeRole(cross(cur), RelayerRole, relayer)
			},
		},
	}

	testing.SetRealm(testing.NewUserRealm(caller))
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, ErrAccessManagerUnauthorizedAccount, func(cur realm) {
				tc.run(cur)
			})
		})
	}
	if HasRole(RelayerRole, caller).IsMember {
		t.Fatal("rejected grant must not add caller")
	}
	if !HasRole(RelayerRole, relayer).IsMember {
		t.Fatal("rejected revoke must not remove relayer")
	}
}

func TestSetFunctionRoleDirectManagement(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	if CanCall(cur.PkgPath(), "set_hook", caller).Immediate {
		t.Fatal("non-admin caller must not be authorized before role update")
	}

	SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)
	if !CanCall(cur.PkgPath(), "set_hook", caller).Immediate {
		t.Fatal("public role assignment must authorize arbitrary caller")
	}
}

func TestSetFunctionRolesDirectManagement(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	selectors := []manager.Selector{"set_hook", "dispatch"}
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	SetFunctionRoles(cross(cur), selectors, manager.PublicRole)

	for _, selector := range selectors {
		t.Run(string(selector), func(t *testing.T) {
			if GetFunctionRole(cur.PkgPath(), selector) != manager.PublicRole {
				t.Fatalf("%s must be assigned public role", selector)
			}
			if GetTargetFunctionRole(cur.PkgPath(), selector) != manager.PublicRole {
				t.Fatalf("%s must be assigned public target role", selector)
			}
			if !CanCall(cur.PkgPath(), selector, caller).Immediate {
				t.Fatalf("%s must authorize arbitrary caller after public role assignment", selector)
			}
		})
	}
}

func TestSetFunctionRoleRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, ErrAccessManagerUnauthorizedAccount, func(cur realm) {
		SetFunctionRole(cur, "set_hook", manager.PublicRole)
	})
	if GetFunctionRole(cur.PkgPath(), "set_hook") != manager.AdminRole {
		t.Fatal("rejected role update must not change selector role")
	}
}

func TestManagerAdminProtectedSurfacesRejectNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	resetAccess(admin)

	tests := []struct {
		name string
		run  func(cur realm)
	}{
		{
			name: "label role",
			run: func(cur realm) {
				LabelRole(cross(cur), RelayerRole, "RELAYER")
			},
		},
		{
			name: "set role admin",
			run: func(cur realm) {
				SetRoleAdmin(cross(cur), RelayerRole, 7)
			},
		},
		{
			name: "set grant delay",
			run: func(cur realm) {
				SetGrantDelay(cross(cur), RelayerRole, 5)
			},
		},
		{
			name: "set function role",
			run: func(cur realm) {
				SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)
			},
		},
		{
			name: "set function roles",
			run: func(cur realm) {
				SetFunctionRoles(cross(cur), []manager.Selector{"set_hook", "dispatch"}, manager.PublicRole)
			},
		},
		{
			name: "set target closed",
			run: func(cur realm) {
				SetTargetClosed(cross(cur), true)
			},
		},
	}

	testing.SetRealm(testing.NewUserRealm(caller))
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, ErrAccessManagerUnauthorizedAccount, func(cur realm) {
				tc.run(cur)
			})
		})
	}
	if GetRoleAdmin(RelayerRole) != manager.AdminRole {
		t.Fatal("rejected SetRoleAdmin must not change role admin")
	}
	if GetRoleGrantDelay(RelayerRole) != 0 {
		t.Fatal("rejected SetGrantDelay must not change grant delay")
	}
	if GetFunctionRole(cur.PkgPath(), "set_hook") != manager.AdminRole {
		t.Fatal("rejected SetFunctionRole must not change selector role")
	}
	if IsTargetClosed(cur.PkgPath()) {
		t.Fatal("rejected SetTargetClosed must not close target")
	}
}

func TestLabelRoleRequiresManagerAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	LabelRole(cross(cur), RelayerRole, "RELAYER")
	label, found := GetRoleLabel(RelayerRole)
	if !found || label != "RELAYER" {
		t.Fatal("LabelRole must store role label")
	}
	labels := GetRoleLabels([]manager.RoleId{RelayerRole, 2})
	if len(labels) != 2 || !labels[0].Found || labels[0].Label != "RELAYER" || labels[1].Found {
		t.Fatal("GetRoleLabels must return stored and missing labels")
	}

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, ErrAccessManagerUnauthorizedAccount, func(cur realm) {
		LabelRole(cross(cur), RelayerRole, "RELAYER")
	})
}

func TestStaticAndFullAccessQueries(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	resetAccess(admin)

	if AdminRole() != manager.AdminRole {
		t.Fatal("AdminRole query must return admin role")
	}
	if PublicRole() != manager.PublicRole {
		t.Fatal("PublicRole query must return public role")
	}
	if Expiration() != manager.OperationExpiration {
		t.Fatal("Expiration query must return operation expiration")
	}
	if MinSetback() != manager.MinSetback {
		t.Fatal("MinSetback query must return min setback")
	}

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRoleWithExecutionDelay(cross(cur), RelayerRole, relayer, 10)
	GrantRoleWithExecutionDelay(cross(cur), RelayerRole, relayer, 6)

	access := GetAccess(RelayerRole, relayer)
	if access.Since.IsZero() || access.CurrentDelay != 10 || access.PendingDelay != 6 || !access.Effect.After(manager.CurrentTimePoint()) {
		t.Fatal("GetAccess must expose full execution delay state")
	}
}

func TestRoleConfigurationSurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	roleAdmin := testutils.TestAddress("access-role-admin")
	relayer := testutils.TestAddress("access-relayer")
	const roleAdminRole manager.RoleId = 7
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), roleAdminRole, roleAdmin)
	SetRoleAdmin(cross(cur), RelayerRole, roleAdminRole)
	SetGrantDelay(cross(cur), RelayerRole, 5)

	if GetRoleAdmin(RelayerRole) != roleAdminRole {
		t.Fatal("SetRoleAdmin must update role admin")
	}
	if GetRoleGrantDelay(RelayerRole) != 0 {
		t.Fatal("SetGrantDelay must defer role grant delay until setback")
	}
	if accessState.Roles[RelayerRole].GrantDelay.ValueAfter != 5 {
		t.Fatal("SetGrantDelay must store pending role grant delay")
	}
	if !CanAdminRole(RelayerRole, roleAdmin).Immediate {
		t.Fatal("role admin member must be able to administer relayer role")
	}

	accessState.Roles[RelayerRole].GrantDelay = manager.NewDelayedValue(0)
	testing.SetRealm(testing.NewUserRealm(roleAdmin))
	GrantRole(cross(cur), RelayerRole, relayer)
	membership := HasRole(RelayerRole, relayer)
	if !membership.IsMember {
		t.Fatal("GrantRole must add active relayer when grant delay is zero")
	}
}

func TestRenounceRoleSurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer)

	testing.SetRealm(testing.NewUserRealm(relayer))
	uassert.AbortsContains(t, cur, "access manager bad confirmation", func(cur realm) {
		RenounceRole(cross(cur), RelayerRole, admin)
	})
	RenounceRole(cross(cur), RelayerRole, relayer)
	if HasRole(RelayerRole, relayer).IsMember {
		t.Fatal("RenounceRole must revoke caller membership")
	}
}

func TestTargetConfigurationSurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)

	if GetTargetFunctionRole(cur.PkgPath(), "set_hook") != manager.PublicRole {
		t.Fatal("SetFunctionRole must update inferred target selector role")
	}
	if !CanManageTarget(admin).Immediate {
		t.Fatal("admin role member must be able to manage targets")
	}
	if !IsAuthorized(cur.PkgPath(), "set_hook", caller) {
		t.Fatal("public selector must authorize arbitrary caller")
	}

	SetTargetClosed(cross(cur), true)
	if !IsTargetClosed(cur.PkgPath()) {
		t.Fatal("SetTargetClosed must close inferred target")
	}
	if CanCall(cur.PkgPath(), "set_hook", caller).Immediate {
		t.Fatal("closed target must reject authorized caller")
	}

	SetTargetClosed(cross(cur), false)
	if !CanCall(cur.PkgPath(), "set_hook", caller).Immediate {
		t.Fatal("reopened target must restore selector authorization")
	}
}

func TestExplicitTargetPathGetters(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	caller := testutils.TestAddress("access-caller")
	resetAccess(admin)
	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer)

	selector := types.RelayerSelectors()[0]
	tests := []struct {
		name string
		run  func() bool
		want bool
	}{
		{
			name: "core target relayer role",
			run: func() bool {
				return GetFunctionRole(CoreRealmPath, selector) == RelayerRole &&
					GetTargetFunctionRole(CoreRealmPath, selector) == RelayerRole
			},
			want: true,
		},
		{
			name: "current target falls back to admin role",
			run: func() bool {
				return GetFunctionRole(cur.PkgPath(), selector) == manager.AdminRole
			},
			want: true,
		},
		{
			name: "relayer authorized for explicit core target",
			run: func() bool {
				return IsAuthorized(CoreRealmPath, selector, relayer)
			},
			want: true,
		},
		{
			name: "ordinary caller rejected for explicit core target",
			run: func() bool {
				return CanCall(CoreRealmPath, selector, caller).Immediate
			},
			want: false,
		},
		{
			name: "core target open by default",
			run: func() bool {
				return IsTargetClosed(CoreRealmPath)
			},
			want: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, tc.run())
		})
	}
}

func TestUnionDeployerRelayerSelectorSetup(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	resetAccess(admin)

	if HasRole(RelayerRole, admin).IsMember {
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
