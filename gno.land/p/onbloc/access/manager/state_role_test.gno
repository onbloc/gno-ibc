package manager

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func TestRoleConfigManagesNilMembersMap(t *testing.T) {
	account := testutils.TestAddress("member")
	roleConfig := &RoleConfig{GrantDelay: NewDelay(5), Members: make(map[address]Access)}
	now := NewTimePoint(100)

	if roleConfig.hasMember(account, now) {
		t.Fatal("missing member must be inactive")
	}
	if !roleConfig.grant(account, now) {
		t.Fatal("first grant must report a new member")
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

	if roleConfig.grant(account, now) {
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

func TestRoleConfigAdmin(t *testing.T) {
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
}

// A grant delay change is not observable until MinSetback has elapsed.
// OpenZeppelin: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L446-L478
// Union: https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/tests.rs#L872-L924
func TestRoleConfigGrantDelayUpdateRespectsSetback(t *testing.T) {
	roleConfig := NewRoleConfig(AdminRole, 0)
	now := NewTimePoint(1_000_000)

	roleConfig.setGrantDelay(now, 10)

	wantEffect := NewTimePoint(now.Int64() + int64(MinSetback))
	if roleConfig.GrantDelay.effectDate != wantEffect {
		t.Fatalf("GrantDelay.EffectDate = %d, want %d", roleConfig.GrantDelay.effectDate.Int64(), wantEffect.Int64())
	}
	if got := roleConfig.grantDelay(now); got != 0 {
		t.Fatalf("grantDelay() before effect = %d, want 0", got)
	}
	if got := roleConfig.grantDelay(NewTimePoint(wantEffect.Int64() - 1)); got != 0 {
		t.Fatalf("grantDelay() one second before effect = %d, want 0", got)
	}
	if got := roleConfig.grantDelay(wantEffect); got != 10 {
		t.Fatalf("grantDelay() at effect = %d, want 10", got)
	}
}

// Regression test: shrinking an active grant delay must not let a
// same-instant grant use the smaller value (see Delay.WithUpdate).
func TestRoleConfigGrantDelayDecreaseCannotBypassObservationWindow(t *testing.T) {
	account := testutils.TestAddress("member")
	const activeDelay uint32 = 86400 // 1 day, already in effect (e.g. an observation window)
	roleConfig := NewRoleConfig(AdminRole, activeDelay)
	now := NewTimePoint(1_000_000)

	roleConfig.setGrantDelay(now, 0) // attempt to shrink the delay to zero...
	roleConfig.grant(account, now)   // ...and grant in the very same instant

	if roleConfig.hasMember(account, now) {
		t.Fatal("shrinking the grant delay must not let a same-instant grant activate immediately")
	}

	activation := NewTimePoint(now.Int64() + int64(activeDelay))
	if !roleConfig.hasMember(account, activation) {
		t.Fatal("member must activate once the delay active at grant time elapses")
	}
}
