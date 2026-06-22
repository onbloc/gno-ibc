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

func TestCanCallDefaultsTargetFunctionToAdminRole(t *testing.T) {
	admin := testutils.TestAddress("admin")
	other := testutils.TestAddress("other")
	state := NewState()
	state.GrantRole(AdminRole, admin, 0)

	if !state.CanCall(admin, "target", "selector").Immediate {
		t.Fatal("admin must be authorized for an unset target function role")
	}
	if state.CanCall(other, "target", "selector").Immediate {
		t.Fatal("non-admin must not be authorized for an unset target function role")
	}
}

func TestPublicRoleAuthorizesEveryAccount(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetTargetFunctionRole("target", "selector", PublicRole)

	if !state.CanCall(caller, "target", "selector").Immediate {
		t.Fatal("public role must authorize every caller")
	}
}

func TestCanCallRejectsClosedTarget(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetTargetFunctionRole("target", "selector", PublicRole)
	state.SetTargetClosed("target", true)

	if state.CanCall(caller, "target", "selector").Immediate {
		t.Fatal("closed target must reject even public selectors")
	}
}

func TestGrantAndRevokeRole(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	if !state.GrantRole(testRole, caller, 0) {
		t.Fatal("first grant must report a new member")
	}
	if !state.HasRole(testRole, caller).IsMember {
		t.Fatal("grant role must add the account")
	}
	if state.GrantRole(testRole, caller, 0) {
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
	state.GrantRole(testRole, caller, 0)

	if state.HasRole(testRole, caller).IsMember {
		t.Fatal("role must not be active before grant delay")
	}
	if !state.Roles[testRole].Members[caller].Since.After(CurrentTimepoint()) {
		t.Fatal("grant delay must set activation after the current timepoint")
	}
}

func TestExecutionDelayMakesCanCallNonImmediate(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.GrantRole(testRole, caller, 7)
	state.SetTargetFunctionRole("target", "selector", testRole)

	result := state.CanCall(caller, "target", "selector")
	if result.Immediate {
		t.Fatal("execution delay must make canCall non-immediate")
	}
	if result.Delay != 7 {
		t.Fatalf("delay: got %d want 7", result.Delay)
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
	state.GrantRole(AdminRole, admin, 0)
	state.SetRoleAdmin(testRole, 2)
	state.GrantRole(2, roleAdmin, 0)

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

	if state.GetTargetFunctionRole("target", "a") != testRole {
		t.Fatal("first selector role not set")
	}
	if state.GetTargetFunctionRole("target", "b") != testRole {
		t.Fatal("second selector role not set")
	}
}

func TestRequireUnlockedConfigRole(t *testing.T) {
	RequireUnlockedConfigRole(testRole)
	mustPanic(t, func() {
		RequireUnlockedConfigRole(AdminRole)
	})
	mustPanic(t, func() {
		RequireUnlockedConfigRole(PublicRole)
	})
}

func TestLockedPublicRoleCannotBeGrantedOrRevoked(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	mustPanic(t, func() {
		state.GrantRole(PublicRole, caller, 0)
	})
	mustPanic(t, func() {
		state.RevokeRole(PublicRole, caller)
	})
}
