package access

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/access/manager"
)

const accessRealmPath = "gno.land/r/onbloc/ibc/union/access"

func TestGrantRoleWithExecutionDelaySurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	relayer := testutils.TestAddress("access-relayer")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRoleWithExecutionDelay(cross(cur), RelayerRole, relayer, 11)

	membership := HasRole(RelayerRole, relayer)
	if !membership.IsMember || membership.ExecutionDelay != 11 {
		t.Fatal("GrantRoleWithExecutionDelay must store role membership and execution delay")
	}

	result := CanCall(CoreRealmPath, manager.Selector("packet_recv"), relayer)
	if result.Immediate || !result.Authorized || result.Delay != 11 {
		t.Fatal("delayed relayer role must authorize with delay for protected core selectors")
	}
}

func TestScheduleAndAssertCanCallOrConsume(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRoleWithExecutionDelay(cross(cur), RelayerRole, caller, 3)
	accessState.SetTargetFunctionRole(accessRealmPath, "delayed_call", RelayerRole)

	target := accessRealmPath
	dataHash := "delayed-call-args"
	operationId := HashOperation(caller, target, "delayed_call", dataHash)
	accessState.Schedules[operationId] = manager.NewSchedule(manager.CurrentTimePoint(), 1)

	testing.SetRealm(testing.NewUserRealm(caller))
	func(cur realm) {
		AssertCanCallOrConsume(0, cur, "delayed_call", dataHash)
	}(cross(cur))

	if GetSchedule(operationId).IsSet() {
		t.Fatal("AssertCanCallOrConsume must consume the ready schedule")
	}
}

func TestScheduleRequiresDelayedAuthorization(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	accessState.SetTargetFunctionRole(accessRealmPath, "public_call", manager.PublicRole)

	testing.SetRealm(testing.NewUserRealm(caller))
	uassert.AbortsContains(t, cur, "access manager unauthorized call", func(cur realm) {
		Schedule(cross(cur), accessRealmPath, "public_call", "args", manager.CurrentTimePoint())
	})

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRoleWithExecutionDelay(cross(cur), RelayerRole, caller, 5)
	accessState.SetTargetFunctionRole(accessRealmPath, "delayed_call", RelayerRole)

	testing.SetRealm(testing.NewUserRealm(caller))
	operationId := Schedule(cross(cur), accessRealmPath, "delayed_call", "args", manager.CurrentTimePoint()+5)
	if !GetSchedule(operationId).IsSet() {
		t.Fatal("Schedule must store delayed operation")
	}
}

func TestRoleGuardianCanCancel(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	guardian := testutils.TestAddress("access-guardian")
	other := testutils.TestAddress("access-other")
	const guardianRole manager.RoleId = 9
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	GrantRole(cross(cur), guardianRole, guardian)
	SetRoleGuardian(cross(cur), RelayerRole, guardianRole)
	accessState.SetTargetFunctionRole(accessRealmPath, "delayed_call", RelayerRole)

	target := accessRealmPath
	dataHash := "cancel-args"
	operationId := HashOperation(caller, target, "delayed_call", dataHash)
	accessState.Schedules[operationId] = manager.NewSchedule(manager.CurrentTimePoint(), 1)

	testing.SetRealm(testing.NewUserRealm(other))
	uassert.AbortsContains(t, cur, "access manager unauthorized call", func(cur realm) {
		Cancel(cross(cur), caller, target, "delayed_call", dataHash)
	})

	testing.SetRealm(testing.NewUserRealm(guardian))
	Cancel(cross(cur), caller, target, "delayed_call", dataHash)
	if GetSchedule(operationId).IsSet() {
		t.Fatal("guardian cancel must clear the schedule")
	}
}

func TestTargetAdminDelaySurface(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	SetTargetAdminDelay(cross(cur), 6)
	if GetTargetAdminDelay(cur.PkgPath()) != 6 {
		t.Fatal("SetTargetAdminDelay must update target delay")
	}
	if CanManageTargetPath(cur.PkgPath(), admin).Immediate {
		t.Fatal("target admin delay must make target management delayed")
	}

	dataHash := "target-closed:true"
	operationId := HashOperation(admin, cur.PkgPath(), manager.SelectorSetTargetClosed, dataHash)
	accessState.Schedules[operationId] = manager.NewSchedule(manager.CurrentTimePoint(), 1)

	SetTargetClosedDelayed(cross(cur), true, dataHash)
	if !IsTargetClosed(cur.PkgPath()) {
		t.Fatal("delayed target close must consume schedule and update target")
	}
	if GetSchedule(operationId).IsSet() {
		t.Fatal("delayed target close must clear consumed schedule")
	}
}
