package manager

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

const testRole RoleId = 1

func mustPanic(t *testing.T, fn func()) {
	t.Helper()
	defer func() {
		if recover() == nil {
			t.Fatal("expected panic")
		}
	}()
	fn()
}

func TestCanCallAuthorization(t *testing.T) {
	admin := testutils.TestAddress("admin")
	other := testutils.TestAddress("other")
	caller := testutils.TestAddress("caller")
	tests := []struct {
		name   string
		caller address
		setup  func(state *State)
		want   bool
	}{
		{
			name:   "unset selector allows admin",
			caller: admin,
			setup: func(state *State) {
				state.GrantRole(AdminRole, admin)
			},
			want: true,
		},
		{
			name:   "unset selector rejects non-admin",
			caller: other,
			setup: func(state *State) {
				state.GrantRole(AdminRole, admin)
			},
			want: false,
		},
		{
			name:   "public role authorizes every account",
			caller: caller,
			setup: func(state *State) {
				state.SetTargetFunctionRole("target", "selector", PublicRole)
			},
			want: true,
		},
		{
			name:   "closed target rejects public selector",
			caller: caller,
			setup: func(state *State) {
				state.SetTargetFunctionRole("target", "selector", PublicRole)
				state.SetTargetClosed("target", true)
			},
			want: false,
		},
		{
			name:   "active member can call",
			caller: caller,
			setup: func(state *State) {
				state.GrantRole(testRole, caller)
				state.SetTargetFunctionRole("target", "selector", testRole)
			},
			want: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			state := NewState()
			tc.setup(&state)

			if got := state.CanCall(tc.caller, "target", "selector").Immediate; got != tc.want {
				t.Fatalf("CanCall() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestGrantAndRevokeRole(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	if !state.GrantRole(testRole, caller) {
		t.Fatal("first grant must report a new member")
	}
	if !state.HasRole(testRole, caller).IsMember {
		t.Fatal("grant role must add the account")
	}
	if state.GrantRole(testRole, caller) {
		t.Fatal("second grant must not report a new member")
	}

	if !state.RevokeRole(testRole, caller) {
		t.Fatal("revoke must report an existing member")
	}
	if state.HasRole(testRole, caller).IsMember {
		t.Fatal("revoke role must remove the account")
	}
	if state.RevokeRole(testRole, caller) {
		t.Fatal("second revoke must report no existing member")
	}
}

func TestGrantDelayDefersMembership(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetGrantDelay(testRole, 10)
	state.GrantRole(testRole, caller)

	if state.HasRole(testRole, caller).IsMember {
		t.Fatal("role must not be active before grant delay")
	}
	if !state.Roles[testRole].Members[caller].Since.After(CurrentTimePoint()) {
		t.Fatal("grant delay must set activation after the current timePoint")
	}
}

func TestGrantRoleForExistingMemberPreservesEffectiveTimePoint(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.GrantRole(testRole, caller)
	previousSince := state.Roles[testRole].Members[caller].Since
	state.SetGrantDelay(testRole, 10)

	if state.GrantRole(testRole, caller) {
		t.Fatal("existing grant must not report a new member")
	}

	access := state.Roles[testRole].Members[caller]
	if !access.Since.Equal(previousSince) {
		t.Fatal("grant delay must not reset an existing member effective timePoint")
	}
	if !state.HasRole(testRole, caller).IsMember {
		t.Fatal("existing member must remain active after repeated grant")
	}
}

func TestRoleAdminDefaultsToAdminRole(t *testing.T) {
	state := NewState()

	if state.GetRoleAdmin(testRole) != AdminRole {
		t.Fatal("role admin must default to admin role")
	}
}

func TestCanAdminRoleUsesRoleAdmin(t *testing.T) {
	admin := testutils.TestAddress("admin")
	roleAdmin := testutils.TestAddress("role-admin")
	state := NewState()
	state.GrantRole(AdminRole, admin)
	state.SetRoleAdmin(testRole, 2)
	state.GrantRole(2, roleAdmin)

	if state.CanAdminRole(testRole, admin).Immediate {
		t.Fatal("global admin must not administer roles after a custom role admin is configured")
	}
	if !state.CanAdminRole(testRole, roleAdmin).Immediate {
		t.Fatal("configured role admin must administer the role")
	}
}

func TestSetTargetFunctionRoles(t *testing.T) {
	state := NewState()
	state.SetTargetFunctionRoles("target", []Selector{"a", "b"}, testRole)

	tests := []struct {
		name     string
		selector Selector
		want     RoleId
	}{
		{"first selector", "a", testRole},
		{"second selector", "b", testRole},
		{"unset selector", "c", AdminRole},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := state.GetTargetFunctionRole("target", tc.selector); got != tc.want {
				t.Fatalf("GetTargetFunctionRole() = %d, want %d", got, tc.want)
			}
		})
	}
}

func TestRequireUnlockedConfigRole(t *testing.T) {
	tests := []struct {
		name      string
		role      RoleId
		wantPanic bool
	}{
		{"regular role", testRole, false},
		{"admin role", AdminRole, true},
		{"public role", PublicRole, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if tc.wantPanic {
				mustPanic(t, func() {
					RequireUnlockedConfigRole(tc.role)
				})
				return
			}
			RequireUnlockedConfigRole(tc.role)
		})
	}
}

func TestLockedPublicRoleCannotBeGrantedOrRevoked(t *testing.T) {
	caller := testutils.TestAddress("caller")
	tests := []struct {
		name string
		call func(state *State)
	}{
		{"grant", func(state *State) { state.GrantRole(PublicRole, caller) }},
		{"revoke", func(state *State) { state.RevokeRole(PublicRole, caller) }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			state := NewState()
			mustPanic(t, func() {
				tc.call(&state)
			})
		})
	}
}

func TestSetGrantDelayRejectsLockedRoles(t *testing.T) {
	tests := []struct {
		name string
		role RoleId
	}{
		{"admin role", AdminRole},
		{"public role", PublicRole},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			state := NewState()
			mustPanic(t, func() {
				state.SetGrantDelay(tc.role, 5)
			})
		})
	}
}

func TestRevokeRoleGuardsLastAdmin(t *testing.T) {
	admin := testutils.TestAddress("admin")
	secondAdmin := testutils.TestAddress("second-admin")

	t.Run("last active admin cannot be revoked", func(t *testing.T) {
		state := NewState()
		state.GrantRole(AdminRole, admin)

		mustPanic(t, func() {
			state.RevokeRole(AdminRole, admin)
		})
		if !state.HasRole(AdminRole, admin).IsMember {
			t.Fatal("last admin must not be removed")
		}
	})

	t.Run("non-last admin can be revoked", func(t *testing.T) {
		state := NewState()
		state.GrantRole(AdminRole, admin)
		state.GrantRole(AdminRole, secondAdmin)

		if !state.RevokeRole(AdminRole, admin) {
			t.Fatal("non-last admin must be revocable")
		}
		if state.HasRole(AdminRole, admin).IsMember {
			t.Fatal("revoked admin must be removed")
		}
		if !state.HasRole(AdminRole, secondAdmin).IsMember {
			t.Fatal("remaining admin must stay active")
		}
	})

	t.Run("renounce last admin is guarded", func(t *testing.T) {
		state := NewState()
		state.GrantRole(AdminRole, admin)

		mustPanic(t, func() {
			state.RenounceRole(AdminRole, admin, admin)
		})
		if !state.HasRole(AdminRole, admin).IsMember {
			t.Fatal("last admin must not be renounced")
		}
	})

	t.Run("non-admin role revoke is unaffected", func(t *testing.T) {
		caller := testutils.TestAddress("caller")
		state := NewState()
		state.GrantRole(testRole, caller)

		if !state.RevokeRole(testRole, caller) {
			t.Fatal("non-admin revoke must succeed")
		}
	})
}
