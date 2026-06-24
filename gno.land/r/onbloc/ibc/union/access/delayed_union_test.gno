package access

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/onbloc/access/manager"
)

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/tests.rs#L2832-L2975
// Gno equivalent surface: AssertCanCallOrConsume.
func TestUnionImmediateAuthorizationConsumesExistingSchedule(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRoleWithExecutionDelay(cross(cur), RelayerRole, caller, 10)
	accessState.SetTargetFunctionRole(accessRealmPath, "delayed_call", RelayerRole)

	target := accessRealmPath
	dataHash := "union-no-delay-consume"

	testing.SetRealm(testing.NewUserRealm(caller))
	operationId := Schedule(cross(cur), target, "delayed_call", dataHash, manager.CurrentTimePoint()+10)
	if !GetSchedule(operationId).IsSet() {
		t.Fatal("schedule must be stored before delay is removed")
	}

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRoleWithExecutionDelay(cross(cur), RelayerRole, caller, 0)
	access := accessState.Roles[RelayerRole].Members[caller]
	access.Delay = manager.NewDelayedValue(0)
	accessState.Roles[RelayerRole].Members[caller] = access

	schedule := accessState.Schedules[operationId]
	schedule.Timepoint = manager.CurrentTimePoint()
	accessState.Schedules[operationId] = schedule

	testing.SetRealm(testing.NewUserRealm(caller))
	func(cur realm) {
		AssertCanCallOrConsume(0, cur, "delayed_call", dataHash)
	}(cross(cur))

	if GetSchedule(operationId).IsSet() {
		t.Fatal("immediate authorization must consume an existing ready schedule")
	}
	if GetNonce(operationId) != 1 {
		t.Fatal("consume must preserve the operation nonce")
	}
}
