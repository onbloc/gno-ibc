package manager

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func TestRoleConfigManagesNilMembersMap(t *testing.T) {
	account := testutils.TestAddress("member")
	roleConfig := &RoleConfig{GrantDelay: 5}
	now := NewTimepoint(100)

	if roleConfig.hasMember(account, now) {
		t.Fatal("missing member must be inactive")
	}
	if !roleConfig.grant(account, now) {
		t.Fatal("first grant must report a new member")
	}
	if roleConfig.Members == nil {
		t.Fatal("grant must initialize members map")
	}
	if roleConfig.hasMember(account, now) {
		t.Fatal("grant delay must keep new member inactive")
	}
	if !roleConfig.hasMember(account, NewTimepoint(105)) {
		t.Fatal("member must become active after grant delay")
	}
	if roleConfig.grant(account, now) {
		t.Fatal("second grant must not report a new member")
	}
	if !roleConfig.revoke(account) {
		t.Fatal("revoke must report an existing member")
	}
	if roleConfig.hasMember(account, NewTimepoint(105)) {
		t.Fatal("revoked member must be inactive")
	}
	if roleConfig.revoke(account) {
		t.Fatal("second revoke must not report an existing member")
	}
}

func TestRoleConfigAdminAndGrantDelay(t *testing.T) {
	roleConfig := NewRoleConfig(AdminRole, 0)

	roleConfig.setAdmin(3)
	if roleConfig.adminRole() != 3 {
		t.Fatal("admin role must return configured role")
	}

	roleConfig.setGrantDelay(7)
	if roleConfig.grantDelay() != 7 {
		t.Fatal("grant delay must return configured delay")
	}
}
