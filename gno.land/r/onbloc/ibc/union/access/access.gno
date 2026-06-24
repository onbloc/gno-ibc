package access

import "gno.land/p/onbloc/access/manager"

var accessState manager.State

// RelayerRole mirrors Union deployer's RELAYER role id.
// Reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65
const RelayerRole manager.RoleId = 1

// GrantRole grants role membership to account through the shared access realm.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L69-L87
func GrantRole(cur realm, role manager.RoleId, account address) bool {
	return GrantRoleWithExecutionDelay(cur, role, account, 0)
}

// GrantRoleWithExecutionDelay grants role membership with a Union-style
// execution delay for calls guarded by that role.
func GrantRoleWithExecutionDelay(cur realm, role manager.RoleId, account address, executionDelay manager.Delay) bool {
	assertCanAdminRole(0, cur, role)

	newMember, effect := accessState.GrantRoleWithExecutionDelayEffect(role, account, executionDelay)

	emitRoleGrantedEvent(role, account, effect, executionDelay, newMember)

	return newMember
}

// RevokeRole revokes role membership from account through the shared access realm.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L89-L100
func RevokeRole(cur realm, role manager.RoleId, account address) bool {
	assertCanAdminRole(0, cur, role)

	revoked := accessState.RevokeRole(role, account)
	if revoked {
		emitRoleRevokedEvent(role, account)
	}

	return revoked
}

// RenounceRole revokes the caller's own role membership after confirmation.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L102-L115
func RenounceRole(cur realm, role manager.RoleId, callerConfirmation address) bool {
	if !cur.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	account := cur.Previous().Address()

	revoked := accessState.RenounceRole(role, account, callerConfirmation)
	if revoked {
		emitRoleRevokedEvent(role, account)
	}

	return revoked
}

// LabelRole emits role label metadata for an unlocked role.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L48-L67
func LabelRole(cur realm, role manager.RoleId, label string) {
	assertCanManageTarget(0, cur)

	manager.RequireUnlockedConfigRole(role)

	emitRoleLabelEvent(role, label)
}

// SetRoleAdmin sets the admin role that can grant or revoke role.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L117-L126
func SetRoleAdmin(cur realm, role manager.RoleId, admin manager.RoleId) {
	assertCanManageTarget(0, cur)

	accessState.SetRoleAdmin(role, admin)

	emitRoleAdminChangedEvent(role, admin)
}

// SetRoleGuardian sets the guardian role that may cancel scheduled operations
// for role.
func SetRoleGuardian(cur realm, role manager.RoleId, guardian manager.RoleId) {
	assertCanManageTarget(0, cur)

	accessState.SetRoleGuardian(role, guardian)

	emitRoleGuardianChangedEvent(role, guardian)
}

// SetGrantDelay sets the delay before future grants of role become active.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L139-L148
func SetGrantDelay(cur realm, role manager.RoleId, delay manager.Delay) {
	assertCanManageTarget(0, cur)

	effect := accessState.SetGrantDelay(role, delay)

	emitRoleGrantDelayChangedEvent(role, delay, effect)
}

// SetFunctionRole sets the role for selector on the calling realm's target path.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L353-L367
func SetFunctionRole(cur realm, selector manager.Selector, role manager.RoleId) {
	assertCanManageTarget(0, cur)

	target := cur.Previous().PkgPath()
	accessState.SetTargetFunctionRole(target, selector, role)

	emitTargetFunctionRoleUpdatedEvent(target, selector, role)
}

func SetFunctionRoleDelayed(cur realm, selector manager.Selector, role manager.RoleId, dataHash string) {
	target := cur.Previous().PkgPath()
	assertCanManageTargetOrConsume(0, cur, target, manager.SelectorSetFunctionRole, dataHash)

	accessState.SetTargetFunctionRole(target, selector, role)

	emitTargetFunctionRoleUpdatedEvent(target, selector, role)
}

// SetFunctionRoles sets the same role for selectors on the calling realm's target path.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L353-L367
func SetFunctionRoles(cur realm, selectors []manager.Selector, role manager.RoleId) {
	assertCanManageTarget(0, cur)

	target := cur.Previous().PkgPath()
	accessState.SetTargetFunctionRoles(target, selectors, role)

	for i := range selectors {
		emitTargetFunctionRoleUpdatedEvent(target, selectors[i], role)
	}
}

func SetFunctionRolesDelayed(cur realm, selectors []manager.Selector, role manager.RoleId, dataHash string) {
	target := cur.Previous().PkgPath()
	assertCanManageTargetOrConsume(0, cur, target, manager.SelectorSetFunctionRoles, dataHash)

	accessState.SetTargetFunctionRoles(target, selectors, role)

	for i := range selectors {
		emitTargetFunctionRoleUpdatedEvent(target, selectors[i], role)
	}
}

// SetTargetAdminDelay sets the delay for future target administration changes
// on the calling realm's target path.
func SetTargetAdminDelay(cur realm, delay manager.Delay) {
	assertCanManageTarget(0, cur)

	target := cur.Previous().PkgPath()
	effect := accessState.SetTargetAdminDelay(target, delay)

	emitTargetAdminDelayUpdatedEvent(target, delay, effect)
}

func SetTargetAdminDelayDelayed(cur realm, delay manager.Delay, dataHash string) {
	target := cur.Previous().PkgPath()
	assertCanManageTargetOrConsume(0, cur, target, manager.SelectorSetTargetAdminDelay, dataHash)

	effect := accessState.SetTargetAdminDelay(target, delay)

	emitTargetAdminDelayUpdatedEvent(target, delay, effect)
}

// SetTargetClosed sets whether the calling realm's target path is closed.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L450-L483
func SetTargetClosed(cur realm, closed bool) {
	assertCanManageTarget(0, cur)

	target := cur.Previous().PkgPath()
	accessState.SetTargetClosed(target, closed)

	emitTargetClosedEvent(target, closed)
}

func SetTargetClosedDelayed(cur realm, closed bool, dataHash string) {
	target := cur.Previous().PkgPath()
	assertCanManageTargetOrConsume(0, cur, target, manager.SelectorSetTargetClosed, dataHash)

	accessState.SetTargetClosed(target, closed)

	emitTargetClosedEvent(target, closed)
}

func Schedule(cur realm, target string, selector manager.Selector, dataHash string, when manager.TimePoint) manager.OperationId {
	if !cur.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	caller := cur.Previous().Address()
	operationId, nonce := accessState.Schedule(caller, target, selector, dataHash, when)

	emitOperationScheduledEvent(operationId, caller, target, selector, dataHash, when, nonce)

	return operationId
}

func ScheduleTargetAdmin(cur realm, target string, selector manager.Selector, dataHash string, when manager.TimePoint) manager.OperationId {
	if !cur.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	caller := cur.Previous().Address()
	operationId, nonce := accessState.ScheduleTargetAdmin(caller, target, selector, dataHash, when)

	emitOperationScheduledEvent(operationId, caller, target, selector, dataHash, when, nonce)

	return operationId
}

func Cancel(cur realm, caller address, target string, selector manager.Selector, dataHash string) manager.OperationId {
	if !cur.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	msgSender := cur.Previous().Address()
	operationId, nonce := accessState.Cancel(msgSender, caller, target, selector, dataHash)

	emitOperationCanceledEvent(operationId, caller, target, selector, dataHash, nonce)

	return operationId
}
