package access

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestResetAccessBootstrapsInitialAdmin(cur realm, t *testing.T) {
	initialAdmin := testutils.TestAddress("access-initial-admin")
	relayer := testutils.TestAddress("access-relayer")
	resetAccess(initialAdmin)

	tests := []struct {
		name string
		ok   func() bool
	}{
		{
			name: "initial admin receives active admin role",
			ok: func() bool {
				return HasRole(cur, manager.AdminRole, initialAdmin).IsMember
			},
		},
		{
			name: "initial admin can manage targets",
			ok: func() bool {
				return CanManageTarget(cur, initialAdmin).Immediate
			},
		},
		{
			name: "initial admin does not receive relayer role",
			ok: func() bool {
				return !HasRole(cur, RelayerRole, initialAdmin).IsMember
			},
		},
		{
			name: "relayer account cannot manage targets by default",
			ok: func() bool {
				return !CanManageTarget(cur, relayer).Immediate
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if !tc.ok() {
				t.Fatal(tc.name)
			}
		})
	}
}

func TestResetAccessUsesDefaultAdminAddress(cur realm, t *testing.T) {
	resetAccess(DefaultAdminAddress)

	tests := []struct {
		name string
		ok   func() bool
	}{
		{
			name: "default admin address receives admin role",
			ok: func() bool {
				return HasRole(cur, manager.AdminRole, DefaultAdminAddress).IsMember
			},
		},
		{
			name: "default admin address can manage targets",
			ok: func() bool {
				return CanManageTarget(cur, DefaultAdminAddress).Immediate
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if !tc.ok() {
				t.Fatal(tc.name)
			}
		})
	}
}

func TestSetupRolesAssignsOnlyRelayerSelectors(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	resetAccess(admin)

	tests := []struct {
		name string
		role manager.RoleId
		list []manager.Selector
	}{
		{
			name: "relayer selectors",
			role: RelayerRole,
			list: types.RelayerSelectors(),
		},
		{
			name: "manager selectors",
			role: manager.AdminRole,
			list: []manager.Selector{"grant_role", "revoke_role", "set_role_admin"},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			for _, selector := range tc.list {
				if accessState.GetTargetFunctionRole(CoreRealmPath, selector) != tc.role {
					t.Fatalf("%s must be initialized with role %d", selector, tc.role)
				}
			}
		})
	}
}
