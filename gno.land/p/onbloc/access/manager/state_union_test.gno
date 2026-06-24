package manager

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

const unionRole RoleId = 61234

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/tests.rs#L771-L869
func TestUnionGrantRoleUpdatesExistingMemberExecutionDelay(t *testing.T) {
	caller := testutils.TestAddress("union-grantee")
	state := NewState()

	if !state.GrantRole(unionRole, caller) {
		t.Fatal("initial grant must report a new member")
	}
	if state.HasRole(unionRole, caller).ExecutionDelay != 0 {
		t.Fatal("initial grant must have zero execution delay")
	}

	if state.GrantRoleWithExecutionDelay(unionRole, caller, 10) {
		t.Fatal("regranting an existing member must not report a new member")
	}
	if state.HasRole(unionRole, caller).ExecutionDelay != 10 {
		t.Fatal("regrant must update existing member execution delay")
	}

	if state.GrantRoleWithExecutionDelay(unionRole, caller, 6) {
		t.Fatal("second regrant must not report a new member")
	}
	access := state.Roles[unionRole].Members[caller]
	now := CurrentTimePoint()
	if access.executionDelayAt(now) != 10 {
		t.Fatal("decreasing execution delay must remain pending before setback")
	}
	if !access.Delay.Effect.After(now) {
		t.Fatal("decreasing execution delay must set a future effect time")
	}
	if access.Delay.Get(access.Delay.Effect) != 6 {
		t.Fatal("decreasing execution delay must apply at effect time")
	}
}

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/tests.rs#L878-L923
func TestUnionSetGrantDelayUsesMinSetback(t *testing.T) {
	state := NewState()

	effect := state.SetGrantDelay(unionRole, 10)
	now := CurrentTimePoint()
	if state.GetRoleGrantDelay(unionRole) != 0 {
		t.Fatal("grant delay must remain unchanged before min setback")
	}
	if !effect.After(now) {
		t.Fatal("grant delay update must have a future effect time")
	}
	if state.Roles[unionRole].GrantDelay.Get(effect) != 10 {
		t.Fatal("grant delay must apply at effect time")
	}
}

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/tests.rs#L2166-L2244
func TestUnionSetTargetAdminDelayUsesMinSetback(t *testing.T) {
	state := NewState()

	effect := state.SetTargetAdminDelay("union-target", 10)
	now := CurrentTimePoint()
	if state.GetTargetAdminDelay("union-target") != 0 {
		t.Fatal("target admin delay must remain unchanged before min setback")
	}
	if !effect.After(now) {
		t.Fatal("target admin delay update must have a future effect time")
	}
	if state.Targets["union-target"].AdminDelay.Get(effect) != 10 {
		t.Fatal("target admin delay must apply at effect time")
	}
}
