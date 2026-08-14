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

// Only the "before minSetback" half is exercised here (State can't
// fast-forward real time); the "after" transition is covered by
// Delay.WithUpdate (delay_test.gno) and state_role_test.gno.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L446-L478
func TestOZGetRoleGrantDelayReturnsConfiguredDelayOrZeroDefault(t *testing.T) {
	state := NewState()

	if state.GetRoleGrantDelay(ozRole) != 0 {
		t.Fatal("unset role grant delay must default to zero")
	}

	state.SetGrantDelay(ozRole, 11)

	if state.GetRoleGrantDelay(ozRole) != 0 {
		t.Fatal("grant delay change must not be observable before its setback effect timePoint")
	}
}

// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L139-L149
func TestOZCanCallClosedTargetReturnsFalse(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()

	state.GrantRole(ozRole, caller)
	state.SetTargetFunctionRole(ozTarget, ozSelector, ozRole)
	state.SetTargetClosed(ozTarget, true)

	result := state.CanCall(caller, ozTarget, ozSelector)
	if result.Immediate {
		t.Fatal("closed target must not be callable")
	}
}

// Gno divergence from OpenZeppelin/Union: both reserve uint64::MAX
// (PUBLIC_ROLE) as a sentinel that every account always holds, that cannot
// be granted/revoked, and that authorizes any caller on an assigned selector.
// This Gno port has no PublicRole concept, so uint64 max is an ordinary role
// like any other — it authorizes only accounts that were explicitly granted
// the role, and it can be granted/revoked freely.
// OpenZeppelin reference (PUBLIC_ROLE constant and its special-cased checks):
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/IAccessManager.sol#L47-L48
// Union reference (PUBLIC_ROLE = u64::MAX):
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/lib.rs#L23-L24
func TestOZUint64MaxRoleIsOrdinaryRoleNotPublic(t *testing.T) {
	const uint64MaxRole RoleId = 18446744073709551615 // uint64 max, formerly manager.PublicRole
	caller := testutils.TestAddress("caller")
	state := NewState()

	state.SetTargetFunctionRole(ozTarget, ozSelector, uint64MaxRole)

	if state.HasRole(uint64MaxRole, caller).IsMember {
		t.Fatal("uint64 max role must not be held by every account (divergence from OZ/Union PUBLIC_ROLE)")
	}
	if state.CanCall(caller, ozTarget, ozSelector).Immediate {
		t.Fatal("uint64 max role must not authorize an ungranted caller (divergence from OZ/Union PUBLIC_ROLE)")
	}

	if !state.GrantRole(uint64MaxRole, caller) {
		t.Fatal("uint64 max role must be grantable like any ordinary role")
	}
	if !state.CanCall(caller, ozTarget, ozSelector).Immediate {
		t.Fatal("granted caller must be authorized once uint64 max role is explicitly granted")
	}
	if !state.RevokeRole(uint64MaxRole, caller) {
		t.Fatal("uint64 max role must be revocable like any ordinary role")
	}
}

// The grant delay is seeded directly since SetGrantDelay's setback needs
// real time to elapse (OZ's own fixture does the equivalent via the
// harness-only $_setGrantDelay plus mining past MINSETBACK).
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L613-L617
func TestOZHasRolePendingGrantReturnsFalse(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.Roles[ozRole] = NewRoleConfig(AdminRole, 10)

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
		state.SetRoleAdmin(AdminRole, AdminRole)
	})
}

// The grant delay is seeded directly for the same reason as
// TestOZHasRolePendingGrantReturnsFalse above.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/test/access/manager/AccessManager.test.js#L1198-L1241
func TestOZGrantRoleWithGrantDelayDefersNewMember(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.Roles[ozRole] = NewRoleConfig(AdminRole, 10)

	if !state.GrantRole(ozRole, caller) {
		t.Fatal("new grant must report a new member")
	}

	access := state.Roles[ozRole].Members[caller]
	if !access.Since.After(CurrentTimePoint()) {
		t.Fatal("grant delay must store a future effective timePoint")
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
}
