package manager

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func TestRoleConfigManagesNilMembersMap(t *testing.T) {
	account := testutils.TestAddress("member")
	roleConfig := &RoleConfig{GrantDelay: NewDelayedValue(5), Members: make(map[address]Access)}
	now := NewTimePoint(100)

	if roleConfig.hasMember(account, now) {
		t.Fatal("missing member must be inactive")
	}
	if !roleConfig.grant(account, now, 3) {
		t.Fatal("first grant must report a new member")
	}
	if roleConfig.Members[account].executionDelayAt(now) != 3 {
		t.Fatal("grant must store execution delay")
	}
	if roleConfig.Members == nil {
		t.Fatal("grant must initialize members map")
	}

	membershipTests := []struct {
		name string
		at   TimePoint
		want bool
	}{
		{"before delay", now, false},
		{"after delay", NewTimePoint(105), true},
	}
	for _, tc := range membershipTests {
		t.Run(tc.name, func(t *testing.T) {
			if got := roleConfig.hasMember(account, tc.at); got != tc.want {
				t.Fatalf("hasMember() = %v, want %v", got, tc.want)
			}
		})
	}

	if roleConfig.grant(account, now, 0) {
		t.Fatal("second grant must not report a new member")
	}
	if !roleConfig.revoke(account) {
		t.Fatal("revoke must report an existing member")
	}
	if roleConfig.hasMember(account, NewTimePoint(105)) {
		t.Fatal("revoked member must be inactive")
	}
	if roleConfig.revoke(account) {
		t.Fatal("second revoke must not report an existing member")
	}
}

func TestRoleConfigAdminAndGrantDelay(t *testing.T) {
	roleConfig := NewRoleConfig(AdminRole, 0)

	adminTests := []struct {
		name string
		role RoleId
	}{
		{"custom admin", 3},
		{"admin role", AdminRole},
	}
	for _, tc := range adminTests {
		t.Run(tc.name, func(t *testing.T) {
			roleConfig.setAdmin(tc.role)
			if got := roleConfig.adminRole(); got != tc.role {
				t.Fatalf("adminRole() = %d, want %d", got, tc.role)
			}
		})
	}

	delayTests := []struct {
		name  string
		delay Delay
	}{
		{"non-zero delay", 7},
		{"zero delay", 0},
	}
	for _, tc := range delayTests {
		t.Run(tc.name, func(t *testing.T) {
			effect := roleConfig.setGrantDelay(tc.delay, NewTimePoint(100))
			if got := roleConfig.grantDelayAt(effect); got != tc.delay {
				t.Fatalf("grantDelay() = %d, want %d", got, tc.delay)
			}
		})
	}

	roleConfig.setGuardian(4)
	if got := roleConfig.guardianRole(); got != 4 {
		t.Fatalf("guardianRole() = %d, want 4", got)
	}
}
