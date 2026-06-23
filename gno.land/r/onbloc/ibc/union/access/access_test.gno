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
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer)
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
		GrantRole(cross(cur), RelayerRole, relayer)
	})
	if HasRole(cur, RelayerRole, relayer).IsMember {
		t.Fatal("rejected grant must not add the relayer")
	}
}

func TestRoleMembershipRejectsNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	relayer := testutils.TestAddress("access-relayer")
	ResetForTest(cur, admin)

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
			uassert.AbortsContains(t, cur, ErrorAccessManagerUnauthorizedAccount, func(cur realm) {
				tc.run(cur)
			})
		})
	}
	if HasRole(cur, RelayerRole, caller).IsMember {
		t.Fatal("rejected grant must not add caller")
	}
	if !HasRole(cur, RelayerRole, relayer).IsMember {
		t.Fatal("rejected revoke must not remove relayer")
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

func TestSetFunctionRolesDirectManagement(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	selectors := []manager.Selector{"set_hook", "dispatch"}
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	SetFunctionRoles(cross(cur), selectors, manager.PublicRole)

	for _, selector := range selectors {
		t.Run(string(selector), func(t *testing.T) {
			if GetFunctionRole(cross(cur), selector) != manager.PublicRole {
				t.Fatalf("%s must be assigned public role", selector)
			}
			if GetTargetFunctionRole(cross(cur), selector) != manager.PublicRole {
				t.Fatalf("%s must be assigned public target role", selector)
			}
			if !CanCall(cross(cur), selector, caller).Immediate {
				t.Fatalf("%s must authorize arbitrary caller after public role assignment", selector)
			}
		})
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

func TestManagerAdminProtectedSurfacesRejectNonAdmin(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-non-admin")
	ResetForTest(cur, admin)

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
			uassert.AbortsContains(t, cur, ErrorAccessManagerUnauthorizedAccount, func(cur realm) {
				tc.run(cur)
			})
		})
	}
	if GetRoleAdmin(cur, RelayerRole) != manager.AdminRole {
		t.Fatal("rejected SetRoleAdmin must not change role admin")
	}
	if GetRoleGrantDelay(cur, RelayerRole) != 0 {
		t.Fatal("rejected SetGrantDelay must not change grant delay")
	}
	if GetFunctionRole(cross(cur), "set_hook") != manager.AdminRole {
		t.Fatal("rejected SetFunctionRole must not change selector role")
	}
	if IsTargetClosed(cross(cur)) {
		t.Fatal("rejected SetTargetClosed must not close target")
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
	GrantRole(cross(cur), roleAdminRole, roleAdmin)
	SetRoleAdmin(cross(cur), RelayerRole, roleAdminRole)
	SetGrantDelay(cross(cur), RelayerRole, 5)

	if GetRoleAdmin(cur, RelayerRole) != roleAdminRole {
		t.Fatal("SetRoleAdmin must update role admin")
	}
	if GetRoleGrantDelay(cur, RelayerRole) != 5 {
		t.Fatal("SetGrantDelay must update role grant delay")
	}
	if !CanAdminRole(cur, RelayerRole, roleAdmin).Immediate {
		t.Fatal("role admin member must be able to administer relayer role")
	}

	SetGrantDelay(cross(cur), RelayerRole, 0)
	testing.SetRealm(testing.NewUserRealm(roleAdmin))
	GrantRole(cross(cur), RelayerRole, relayer)
	membership := HasRole(cur, RelayerRole, relayer)
	if !membership.IsMember {
		t.Fatal("GrantRole must add active relayer when grant delay is zero")
	}
}

func TestRenounceRoleSurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), RelayerRole, relayer)

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

	if GetTargetFunctionRole(cross(cur), "set_hook") != manager.PublicRole {
		t.Fatal("SetFunctionRole must update inferred target selector role")
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

func TestAssertCanCall(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	ResetForTest(cur, admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)

	tests := []struct {
		name    string
		setup   func(cur realm)
		aborts  bool
		message string
	}{
		{
			name: "authorized public selector",
			setup: func(cur realm) {
				SetTargetClosed(cross(cur), false)
			},
		},
		{
			name: "closed target",
			setup: func(cur realm) {
				SetTargetClosed(cross(cur), true)
			},
			aborts:  true,
			message: ErrorAccessManagerUnauthorizedCall,
		},
		{
			name: "admin selector without role",
			setup: func(cur realm) {
				SetTargetClosed(cross(cur), false)
			},
			aborts:  true,
			message: ErrorAccessManagerUnauthorizedCall,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			testing.SetRealm(testing.NewUserRealm(admin))
			tc.setup(cur)

			if tc.aborts {
				uassert.AbortsContains(t, cur, tc.message, func(cur realm) {
					if tc.name == "admin selector without role" {
						AssertCanCall(cross(cur), "grant_role", caller)
					} else {
						AssertCanCall(cross(cur), "set_hook", caller)
					}
				})
			} else {
				AssertCanCall(cross(cur), "set_hook", caller)
			}
		})
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
