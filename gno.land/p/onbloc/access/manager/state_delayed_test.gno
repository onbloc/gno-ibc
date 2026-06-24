package manager

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func TestExecutionDelayRequiresSchedule(t *testing.T) {
	caller := testutils.TestAddress("delayed-caller")
	state := NewState()
	state.GrantRoleWithExecutionDelay(testRole, caller, 5)
	state.SetTargetFunctionRole("target", "selector", testRole)

	result := state.CanCall(caller, "target", "selector")
	if result.Immediate || !result.Authorized || result.Delay != 5 {
		t.Fatal("execution delay must authorize with delayed result")
	}
	if state.IsAuthorized(caller, "target", "selector") {
		t.Fatal("delayed authorization must not be immediate authorization")
	}

	when := CurrentTimePoint() + 5
	operationId, nonce := state.Schedule(caller, "target", "selector", "args", when)
	if operationId != HashOperation(caller, "target", "selector", "args") {
		t.Fatal("schedule must use the deterministic operation id")
	}
	if nonce != 1 {
		t.Fatal("first schedule nonce must be one")
	}
	if !state.Schedules[operationId].Timepoint.Equal(when) {
		t.Fatal("schedule must store the requested timepoint")
	}
}

func TestScheduleRejectsImmediateAndInsufficientDelay(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.GrantRole(testRole, caller)
	state.SetTargetFunctionRole("target", "selector", testRole)

	mustPanic(t, func() {
		state.Schedule(caller, "target", "selector", "args", CurrentTimePoint())
	})

	state = NewState()
	state.GrantRoleWithExecutionDelay(testRole, caller, 10)
	state.SetTargetFunctionRole("target", "selector", testRole)
	mustPanic(t, func() {
		state.Schedule(caller, "target", "selector", "args", CurrentTimePoint()+9)
	})
}

func TestConsumeScheduledOperation(t *testing.T) {
	caller := testutils.TestAddress("caller")
	state := NewState()
	state.GrantRoleWithExecutionDelay(testRole, caller, 0)
	state.SetTargetFunctionRole("target", "selector", testRole)

	when := CurrentTimePoint()
	operationId := HashOperation(caller, "target", "selector", "args")
	state.Schedules[operationId] = NewSchedule(when, 7)

	consumedId, nonce := state.ConsumeScheduledOp(caller, "target", "selector", "args")
	if consumedId != operationId || nonce != 7 {
		t.Fatal("consume must return the consumed operation id and nonce")
	}
	if state.Schedules[operationId].IsSet() {
		t.Fatal("consume must clear the schedule timepoint")
	}
	mustPanic(t, func() {
		state.ConsumeScheduledOp(caller, "target", "selector", "args")
	})
}

func TestCancelScheduledOperationByCallerAdminOrGuardian(t *testing.T) {
	caller := testutils.TestAddress("caller")
	admin := testutils.TestAddress("admin")
	guardian := testutils.TestAddress("guardian")
	other := testutils.TestAddress("other")
	state := NewState()
	state.GrantRole(AdminRole, admin)
	state.GrantRole(3, guardian)
	state.SetRoleGuardian(testRole, 3)
	state.SetTargetFunctionRole("target", "selector", testRole)

	for _, msgSender := range []address{caller, admin, guardian} {
		operationId := HashOperation(caller, "target", "selector", msgSender.String())
		state.Schedules[operationId] = NewSchedule(CurrentTimePoint(), 1)
		state.Cancel(msgSender, caller, "target", "selector", msgSender.String())
		if state.Schedules[operationId].IsSet() {
			t.Fatal("authorized cancel must clear schedule")
		}
	}

	operationId := HashOperation(caller, "target", "selector", "blocked")
	state.Schedules[operationId] = NewSchedule(CurrentTimePoint(), 1)
	mustPanic(t, func() {
		state.Cancel(other, caller, "target", "selector", "blocked")
	})
}

func TestTargetAdminDelaySchedulesTargetConfiguration(t *testing.T) {
	admin := testutils.TestAddress("admin")
	state := NewState()
	state.GrantRole(AdminRole, admin)
	state.SetTargetAdminDelay("target", 8)

	result := state.CanManageTargetPath(admin, "target")
	if result.Immediate || !result.Authorized || result.Delay != 8 {
		t.Fatal("target admin delay must require delayed target management")
	}

	when := CurrentTimePoint() + 8
	operationId, nonce := state.ScheduleTargetAdmin(admin, "target", SelectorSetTargetClosed, "closed:true", when)
	if nonce != 1 {
		t.Fatal("first target admin schedule nonce must be one")
	}
	if !state.Schedules[operationId].Timepoint.Equal(when) {
		t.Fatal("target admin schedule must store the requested timepoint")
	}
}
