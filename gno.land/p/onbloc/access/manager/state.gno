package manager

import "gno.land/p/nt/ufmt/v0"

type State struct {
	Roles     map[RoleId]*RoleConfig
	Targets   map[string]*TargetConfig
	Schedules map[OperationId]Schedule
	Labels    map[RoleId]string
}

func NewState() State {
	return State{
		Roles:     make(map[RoleId]*RoleConfig),
		Targets:   make(map[string]*TargetConfig),
		Schedules: make(map[OperationId]Schedule),
		Labels:    make(map[RoleId]string),
	}
}

// =================================================== GETTERS ====================================================

// CanCall reports whether caller can call target selector immediately or after
// the caller's configured execution delay.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L140-L156
func (state *State) CanCall(caller address, target string, selector Selector) CanCallResult {
	if state.IsTargetClosed(target) {
		return NewCanCallResult(false)
	}

	role := state.GetTargetFunctionRole(target, selector)

	membership := state.HasRole(role, caller)
	if !membership.IsMember {
		return NewCanCallResult(false)
	}

	if membership.ExecutionDelay > 0 {
		return NewDelayedCanCallResult(membership.ExecutionDelay)
	}

	return NewCanCallResult(true)
}

// IsAuthorized is a boolean convenience wrapper around CanCall.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L140-L156
func (state *State) IsAuthorized(caller address, target string, selector Selector) bool {
	return state.CanCall(caller, target, selector).Immediate
}

// HasRole reports whether account currently has an active role membership and
// its execution delay.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L211-L220
func (state *State) HasRole(role RoleId, account address) HasRoleResult {
	if role == PublicRole {
		return NewHasRoleResult(true)
	}

	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return NewHasRoleResult(false)
	}

	now := CurrentTimePoint()
	storedAccess := roleConfig.rawAccess(account)
	if storedAccess.Since.IsZero() {
		return NewHasRoleResult(false)
	}

	access := roleConfig.access(account, now)
	if access.Since.IsZero() {
		return NewHasRoleResultWithDelay(false, storedAccess.executionDelayAt(now))
	}

	return NewHasRoleResultWithDelay(true, access.executionDelayAt(now))
}

// GetRoleAdmin returns the admin role for role, defaulting to AdminRole.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L183-L186
func (state *State) GetRoleAdmin(role RoleId) RoleId {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return AdminRole
	}

	return roleConfig.adminRole()
}

// GetRoleGuardian returns the guardian role allowed to cancel delayed
// operations for role.
func (state *State) GetRoleGuardian(role RoleId) RoleId {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return AdminRole
	}

	return roleConfig.guardianRole()
}

// GetRoleGrantDelay returns the grant delay configured for role.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L193-L196
func (state *State) GetRoleGrantDelay(role RoleId) Delay {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return 0
	}

	return roleConfig.grantDelayAt(CurrentTimePoint())
}

// GetTargetFunctionRole returns the role required for target selector.
// Unconfigured selectors default to AdminRole in this Gno representation.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L173-L176
func (state *State) GetTargetFunctionRole(target string, selector Selector) RoleId {
	targetConfig := state.getTarget(target)
	if targetConfig == nil {
		return AdminRole
	}

	return targetConfig.functionRole(selector)
}

// GetTargetAdminDelay returns the delay required before target configuration
// changes can be consumed.
func (state *State) GetTargetAdminDelay(target string) Delay {
	targetConfig := state.getTarget(target)
	if targetConfig == nil {
		return 0
	}

	return targetConfig.adminDelayAt(CurrentTimePoint())
}

// IsTargetClosed reports whether target is closed.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L168-L171
func (state *State) IsTargetClosed(target string) bool {
	targetConfig := state.getTarget(target)

	return targetConfig != nil && targetConfig.isClosed()
}

func (state *State) GetSchedule(operationId OperationId) Schedule {
	schedule := state.getSchedule(operationId)
	if schedule.isExpired(CurrentTimePoint()) {
		schedule.Timepoint = 0
	}

	return schedule
}

func (state *State) GetNonce(operationId OperationId) Nonce {
	return state.getSchedule(operationId).Nonce
}

func (state *State) GetAccess(role RoleId, account address) FullAccess {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return Access{}.fullAt(CurrentTimePoint())
	}

	return roleConfig.rawAccess(account).fullAt(CurrentTimePoint())
}

func (state *State) GetRoleLabel(role RoleId) (string, bool) {
	if state.Labels == nil {
		state.Labels = make(map[RoleId]string)
	}

	label, found := state.Labels[role]
	return label, found
}

func (state *State) GetRoleLabels(roles []RoleId) []RoleLabel {
	labels := make([]RoleLabel, len(roles))
	for i := range roles {
		label, found := state.GetRoleLabel(roles[i])
		labels[i] = RoleLabel{
			Role:  roles[i],
			Label: label,
			Found: found,
		}
	}

	return labels
}

// =============================================== ROLE MANAGEMENT ===============================================

func (state *State) LabelRole(role RoleId, label string) {
	RequireUnlockedConfigRole(role)
	if state.Labels == nil {
		state.Labels = make(map[RoleId]string)
	}

	state.Labels[role] = label
}

// GrantRole grants role membership to account and returns true for a new member.
// This Gno port retains grant delay and execution delay in a Gno-native state
// transition library.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L233-L236
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L271-L298
func (state *State) GrantRole(role RoleId, account address) bool {
	return state.GrantRoleWithExecutionDelay(role, account, 0)
}

// GrantRoleWithExecutionDelay grants role membership to account with a call
// execution delay after the membership becomes active.
func (state *State) GrantRoleWithExecutionDelay(role RoleId, account address, executionDelay Delay) bool {
	newMember, _ := state.GrantRoleWithExecutionDelayEffect(role, account, executionDelay)

	return newMember
}

func (state *State) GrantRoleWithExecutionDelayEffect(role RoleId, account address, executionDelay Delay) (bool, TimePoint) {
	if role == PublicRole {
		panic(errorWithDetails(errAccessManagerLockedRole, ufmt.Sprintf("role %d is locked", role)))
	}

	state.ensureRole(role)

	return state.getRole(role).grantWithEffect(account, CurrentTimePoint(), executionDelay)
}

// RevokeRole revokes role membership from account and reports whether it existed.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L238-L240
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L300-L319
func (state *State) RevokeRole(role RoleId, account address) bool {
	if role == PublicRole {
		panic(errorWithDetails(errAccessManagerLockedRole, ufmt.Sprintf("role %d is locked", role)))
	}

	state.ensureRole(role)

	return state.getRole(role).revoke(account)
}

// RenounceRole revokes caller-confirmed role membership from account.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L243-L249
func (state *State) RenounceRole(role RoleId, account address, callerConfirmation address) bool {
	if account != callerConfirmation {
		panic(errAccessManagerBadConfirmation)
	}

	return state.RevokeRole(role, account)
}

// SetRoleAdmin sets the admin role that can grant or revoke role.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L251-L254
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L321-L337
func (state *State) SetRoleAdmin(role RoleId, admin RoleId) {
	RequireUnlockedConfigRole(role)

	state.ensureRole(role)
	state.getRole(role).setAdmin(admin)
}

// SetRoleGuardian sets the role that can cancel scheduled operations requiring
// role.
func (state *State) SetRoleGuardian(role RoleId, guardian RoleId) {
	RequireUnlockedConfigRole(role)

	state.ensureRole(role)
	state.getRole(role).setGuardian(guardian)
}

// SetGrantDelay sets the delay before future grants of role become active.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L261-L264
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L357-L371
func (state *State) SetGrantDelay(role RoleId, delay Delay) TimePoint {
	if role == PublicRole {
		panic(errorWithDetails(errAccessManagerLockedRole, ufmt.Sprintf("role %d is locked", role)))
	}

	state.ensureRole(role)
	return state.getRole(role).setGrantDelay(delay, CurrentTimePoint())
}

// ============================================= FUNCTION MANAGEMENT ==============================================

// SetTargetFunctionRole sets the role required for target selector.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L385-L393
func (state *State) SetTargetFunctionRole(target string, selector Selector, role RoleId) {
	state.ensureTarget(target)
	state.getTarget(target).setFunctionRole(selector, role)
}

// SetTargetFunctionRoles sets the same role for multiple target selectors.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L373-L383
func (state *State) SetTargetFunctionRoles(target string, selectors []Selector, role RoleId) {
	state.ensureTarget(target)
	state.getTarget(target).setFunctionRoles(selectors, role)
}

// SetTargetAdminDelay sets the delay required before target configuration
// operations can be consumed.
func (state *State) SetTargetAdminDelay(target string, delay Delay) TimePoint {
	state.ensureTarget(target)
	return state.getTarget(target).setAdminDelayWithSetback(delay, CurrentTimePoint())
}

// =============================================== MODE MANAGEMENT ================================================

// SetTargetClosed sets whether target rejects calls regardless of selector role.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L412-L416
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L418-L426
func (state *State) SetTargetClosed(target string, closed bool) {
	state.ensureTarget(target)
	state.getTarget(target).setClosed(closed)
}

// ============================================= DELAYED OPERATIONS ================================================

func (state *State) Schedule(caller address, target string, selector Selector, dataHash string, when TimePoint) (OperationId, Nonce) {
	result := state.CanCall(caller, target, selector)
	if !result.Authorized || result.Immediate {
		panic(errAccessManagerUnauthorizedCall)
	}

	return state.scheduleWithDelay(caller, target, selector, dataHash, when, result.Delay)
}

func (state *State) ScheduleTargetAdmin(caller address, target string, selector Selector, dataHash string, when TimePoint) (OperationId, Nonce) {
	result := state.CanManageTargetPath(caller, target)
	if !result.Authorized || result.Immediate {
		panic(errAccessManagerUnauthorizedCall)
	}

	return state.scheduleWithDelay(caller, target, selector, dataHash, when, result.Delay)
}

func (state *State) Cancel(msgSender address, caller address, target string, selector Selector, dataHash string) (OperationId, Nonce) {
	operationId := HashOperation(caller, target, selector, dataHash)
	schedule := state.getSchedule(operationId)
	if !schedule.IsSet() {
		panic(errAccessManagerNotScheduled)
	}

	if msgSender != caller && !state.HasRole(AdminRole, msgSender).IsMember {
		requiredRole := state.GetTargetFunctionRole(target, selector)
		guardianRole := state.GetRoleGuardian(requiredRole)
		if !state.HasRole(guardianRole, msgSender).IsMember {
			panic(errAccessManagerUnauthorizedCall)
		}
	}

	schedule.Timepoint = 0
	state.Schedules[operationId] = schedule

	return operationId, schedule.Nonce
}

func (state *State) ConsumeScheduledOp(caller address, target string, selector Selector, dataHash string) (OperationId, Nonce) {
	operationId := HashOperation(caller, target, selector, dataHash)
	schedule := state.getSchedule(operationId)
	if !schedule.IsSet() {
		panic(errAccessManagerNotScheduled)
	}

	now := CurrentTimePoint()
	if !schedule.isReady(now) {
		panic(errAccessManagerNotReady)
	}
	if schedule.isExpired(now) {
		panic(errAccessManagerExpired)
	}

	schedule.Timepoint = 0
	state.Schedules[operationId] = schedule

	return operationId, schedule.Nonce
}

// ================================================= ADMIN LOGIC ==================================================

// CanAdminRole reports whether caller has the admin role required for role.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L652-L657
func (state *State) CanAdminRole(role RoleId, caller address) CanCallResult {
	adminRole := state.GetRoleAdmin(role)

	membership := state.HasRole(adminRole, caller)
	if !membership.IsMember {
		return NewCanCallResult(false)
	}

	if membership.ExecutionDelay > 0 {
		return NewDelayedCanCallResult(membership.ExecutionDelay)
	}

	return NewCanCallResult(true)
}

// CanManageTarget reports whether caller can manage target configuration.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L101-L105
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L640-L650
func (state *State) CanManageTarget(caller address) CanCallResult {
	membership := state.HasRole(AdminRole, caller)
	if !membership.IsMember {
		return NewCanCallResult(false)
	}

	if membership.ExecutionDelay > 0 {
		return NewDelayedCanCallResult(membership.ExecutionDelay)
	}

	return NewCanCallResult(true)
}

func (state *State) CanManageTargetPath(caller address, target string) CanCallResult {
	result := state.CanManageTarget(caller)
	if !result.Authorized || !result.Immediate {
		return result
	}

	adminDelay := state.GetTargetAdminDelay(target)
	if adminDelay > 0 {
		return NewDelayedCanCallResult(adminDelay)
	}

	return result
}

func (state *State) getRole(role RoleId) *RoleConfig {
	return state.Roles[role]
}

func (state *State) getTarget(target string) *TargetConfig {
	return state.Targets[target]
}

func (state *State) getSchedule(operationId OperationId) Schedule {
	if state.Schedules == nil {
		state.Schedules = make(map[OperationId]Schedule)
	}

	return state.Schedules[operationId]
}

func (state *State) scheduleWithDelay(caller address, target string, selector Selector, dataHash string, when TimePoint, delay Delay) (OperationId, Nonce) {
	now := CurrentTimePoint()
	if when.Before(now + TimePoint(delay)) {
		panic(errAccessManagerInsufficientDelay)
	}

	if state.Schedules == nil {
		state.Schedules = make(map[OperationId]Schedule)
	}

	operationId := HashOperation(caller, target, selector, dataHash)
	current := state.Schedules[operationId]
	if current.IsSet() && !current.isExpired(now) {
		panic(errAccessManagerAlreadyScheduled)
	}

	nonce := current.Nonce + 1
	state.Schedules[operationId] = NewSchedule(when, nonce)

	return operationId, nonce
}

func (state *State) ensureRole(role RoleId) {
	roleConfig, found := state.Roles[role]
	if !found || roleConfig == nil {
		state.Roles[role] = NewRoleConfig(AdminRole, 0)
	}
}

func (state *State) ensureTarget(target string) {
	targetConfig, found := state.Targets[target]
	if !found || targetConfig == nil {
		state.Targets[target] = NewTargetConfig(false)
	}
}
