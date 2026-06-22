package manager

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

const (
	ozRole      RoleId   = 49832
	ozAdminRole RoleId   = 789433
	ozTarget    string   = "target"
	ozSelector  Selector = "0x12345678"
)

// OpenZeppelin tests for account execution delay and target admin delay are
// intentionally not ported while the Gno manager excludes delayed execution.

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L369-L378
func TestOZGetTargetFunctionRoleReturnsConfiguredRoleOrAdminDefault(t *testing.T) {
	state := NewState()

	if state.GetTargetFunctionRole(ozTarget, ozSelector) != AdminRole {
		t.Fatal("unset target function role must default to admin role")
	}

	state.SetTargetFunctionRole(ozTarget, ozSelector, ozRole)
	if state.GetTargetFunctionRole(ozTarget, ozSelector) != ozRole {
		t.Fatal("target function role must return the configured role")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L414-L427
func TestOZGetRoleAdminReturnsConfiguredAdminOrAdminDefault(t *testing.T) {
	state := NewState()

	if state.GetRoleAdmin(ozRole) != AdminRole {
		t.Fatal("unset role admin must default to admin role")
	}

	state.SetRoleAdmin(ozRole, ozAdminRole)
	if state.GetRoleAdmin(ozRole) != ozAdminRole {
		t.Fatal("role admin must return the configured admin role")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L446-L478
func TestOZGetRoleGrantDelayReturnsConfiguredDelayOrZeroDefault(t *testing.T) {
	state := NewState()

	if state.GetRoleGrantDelay(ozRole) != 0 {
		t.Fatal("unset role grant delay must default to zero")
	}

	state.SetGrantDelay(ozRole, 11)
	if state.GetRoleGrantDelay(ozRole) != 11 {
		t.Fatal("role grant delay must return the configured delay")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L139-L149
func TestOZCanCallClosedTargetReturnsFalse(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetTargetFunctionRole(ozTarget, ozSelector, PublicRole)
	state.SetTargetClosed(ozTarget, true)

	result := state.CanCall(caller, ozTarget, ozSelector)
	if result.Immediate {
		t.Fatal("closed target must not be callable")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L177-L186
func TestOZCanCallPublicRoleReturnsTrue(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetTargetFunctionRole(ozTarget, ozSelector, PublicRole)

	result := state.CanCall(caller, ozTarget, ozSelector)
	if !result.Immediate {
		t.Fatal("public role target must be callable immediately")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L591-L604
func TestOZHasRolePublicRoleReturnsTrue(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	result := state.HasRole(PublicRole, caller)
	if !result.IsMember {
		t.Fatal("public role must be held by every account")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L613-L617
func TestOZHasRolePendingGrantReturnsFalse(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetGrantDelay(ozRole, 10)
	state.GrantRole(ozRole, caller)

	result := state.HasRole(ozRole, caller)
	if result.IsMember {
		t.Fatal("grant delay must keep role inactive before effect")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L650-L663
func TestOZHasRoleGrantedRoleReturnsTrue(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.GrantRole(ozRole, caller)

	result := state.HasRole(ozRole, caller)
	if !result.IsMember {
		t.Fatal("granted role must be active without grant delay")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L667-L672
func TestOZHasRoleMissingRoleReturnsFalse(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	result := state.HasRole(ozRole, caller)
	if result.IsMember {
		t.Fatal("missing role must not be active")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L823-L843
func TestOZSetRoleAdminSetsUnlockedRoleAndRejectsLockedRoles(t *testing.T) {
	state := NewState()
	state.SetRoleAdmin(ozRole, ozAdminRole)
	if state.GetRoleAdmin(ozRole) != ozAdminRole {
		t.Fatal("unlocked role admin must be configurable")
	}

	mustPanic(t, func() {
		state.SetRoleAdmin(PublicRole, AdminRole)
	})
	mustPanic(t, func() {
		state.SetRoleAdmin(AdminRole, AdminRole)
	})
}

// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L891-L894
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L362-L365
func TestOZSetGrantDelayRejectsPublicRole(t *testing.T) {
	state := NewState()

	mustPanic(t, func() {
		state.SetGrantDelay(PublicRole, 69)
	})
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1191-L1194
func TestOZGrantRoleRejectsPublicRole(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	mustPanic(t, func() {
		state.GrantRole(PublicRole, caller)
	})
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1198-L1241
func TestOZGrantRoleWithGrantDelayDefersNewMember(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetGrantDelay(ozRole, 10)

	if !state.GrantRole(ozRole, caller) {
		t.Fatal("new grant must report a new member")
	}

	access := state.Roles[ozRole].Members[caller]
	if !access.Since.After(CurrentTimepoint()) {
		t.Fatal("grant delay must store a future effective timepoint")
	}

	result := state.HasRole(ozRole, caller)
	if result.IsMember {
		t.Fatal("new member must not be active before grant delay")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1280-L1307
func TestOZGrantRoleWithoutGrantDelayActivatesNewMember(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	if !state.GrantRole(ozRole, caller) {
		t.Fatal("new grant must report a new member")
	}

	result := state.HasRole(ozRole, caller)
	if !result.IsMember {
		t.Fatal("new member must be active without grant delay")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1569-L1589
func TestOZRevokeRoleRemovesPendingGrant(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.SetGrantDelay(ozRole, 10)
	state.GrantRole(ozRole, caller)

	if !state.RevokeRole(ozRole, caller) {
		t.Fatal("revoke must report a previously granted pending member")
	}

	result := state.HasRole(ozRole, caller)
	if result.IsMember {
		t.Fatal("revoked role must not be active")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1619-L1633
func TestOZRevokeRoleMissingRoleHasNoEffect(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	if state.RevokeRole(ozRole, caller) {
		t.Fatal("revoke must report false when role was not granted")
	}

	result := state.HasRole(ozRole, caller)
	if result.IsMember {
		t.Fatal("missing role must remain inactive")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1636-L1639
func TestOZRevokeRoleRejectsPublicRole(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	mustPanic(t, func() {
		state.RevokeRole(PublicRole, caller)
	})
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1652-L1675
func TestOZRenounceRoleRevokesAndRejectsBadConfirmation(t *testing.T) {
	caller := testutils.TestAddress("caller")
	other := testutils.TestAddress("other")
	state := NewState()
	state.GrantRole(ozRole, caller)

	if !state.RenounceRole(ozRole, caller, caller) {
		t.Fatal("renounce must report a previously granted member")
	}
	if state.HasRole(ozRole, caller).IsMember {
		t.Fatal("renounced role must be inactive")
	}

	state.GrantRole(ozRole, caller)
	mustPanic(t, func() {
		state.RenounceRole(ozRole, caller, other)
	})
	mustPanic(t, func() {
		state.RenounceRole(PublicRole, caller, caller)
	})
}
