package manager

func (state *State) GrantRole(role RoleId, account address, executionDelay Delay) bool {
	if role == PublicRole {
		panic(AccessManagerLockedRoleError(role))
	}
	roleConfig := state.ensureRole(role)
	_, found := roleConfig.Members[account]
	roleConfig.Members[account] = NewAccess(CurrentTimepoint().availableAt(roleConfig.GrantDelay), executionDelay)
	return !found
}

func (state *State) RevokeRole(role RoleId, account address) bool {
	if role == PublicRole {
		panic(AccessManagerLockedRoleError(role))
	}
	roleConfig := state.ensureRole(role)
	_, found := roleConfig.Members[account]
	if found {
		delete(roleConfig.Members, account)
	}
	return found
}

func (state *State) RenounceRole(role RoleId, account address, callerConfirmation address) bool {
	if account != callerConfirmation {
		panic(ErrorAccessManagerBadConfirmation)
	}
	return state.RevokeRole(role, account)
}

func (state *State) HasRole(role RoleId, account address) HasRoleResult {
	if role == PublicRole {
		return NewHasRoleResult(true, 0)
	}
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return NewHasRoleResult(false, 0)
	}
	access, found := roleConfig.Members[account]
	if !found || access.Since == 0 || access.Since > CurrentTimepoint() {
		return NewHasRoleResult(false, 0)
	}
	return NewHasRoleResult(true, access.ExecutionDelay)
}

func (state *State) SetRoleAdmin(role RoleId, admin RoleId) {
	requireUnlockedConfigRole(role)
	state.ensureRole(role).Admin = admin
}

func (state *State) GetRoleAdmin(role RoleId) RoleId {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return AdminRole
	}
	return roleConfig.Admin
}

func (state *State) SetRoleGuardian(role RoleId, guardian RoleId) {
	requireUnlockedConfigRole(role)
	state.ensureRole(role).Guardian = guardian
}

func (state *State) GetRoleGuardian(role RoleId) RoleId {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return AdminRole
	}
	return roleConfig.Guardian
}

func (state *State) SetGrantDelay(role RoleId, delay Delay) {
	if role == PublicRole {
		panic(AccessManagerLockedRoleError(role))
	}
	state.ensureRole(role).GrantDelay = delay
}

func (state *State) GetRoleGrantDelay(role RoleId) Delay {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return 0
	}
	return roleConfig.GrantDelay
}

func (state *State) LabelRole(role RoleId, label string) {
	requireUnlockedConfigRole(role)
	emitRoleLabelEvent(role, label)
}

func (state *State) SetTargetFunctionRole(target string, selector Selector, role RoleId) {
	state.ensureTarget(target).FunctionRoles[selector] = role
}

func (state *State) SetTargetFunctionRoles(target string, selectors []Selector, role RoleId) {
	for i := range selectors {
		state.SetTargetFunctionRole(target, selectors[i], role)
	}
}

func (state *State) GetTargetFunctionRole(target string, selector Selector) RoleId {
	targetConfig := state.getTarget(target)
	if targetConfig == nil {
		return AdminRole
	}
	role, found := targetConfig.FunctionRoles[selector]
	if !found {
		return AdminRole
	}
	return role
}

func (state *State) SetTargetAdminDelay(target string, delay Delay) {
	state.ensureTarget(target).AdminDelay = delay
}

func (state *State) GetTargetAdminDelay(target string) Delay {
	targetConfig := state.getTarget(target)
	if targetConfig == nil {
		return 0
	}
	return targetConfig.AdminDelay
}

func (state *State) SetTargetClosed(target string, closed bool) {
	state.ensureTarget(target).Closed = closed
}

func (state *State) IsTargetClosed(target string) bool {
	targetConfig := state.getTarget(target)
	return targetConfig != nil && targetConfig.Closed
}

func (state *State) CanCall(caller address, target string, selector Selector) CanCallResult {
	if state.IsTargetClosed(target) {
		return NewCanCallResult(false, 0)
	}
	role := state.GetTargetFunctionRole(target, selector)
	membership := state.HasRole(role, caller)
	if !membership.IsMember {
		return NewCanCallResult(false, 0)
	}
	return NewCanCallResult(membership.ExecutionDelay == 0, membership.ExecutionDelay)
}

func (state *State) IsAuthorized(caller address, target string, selector Selector) bool {
	return state.CanCall(caller, target, selector).Immediate
}

func (state *State) CanAdminRole(role RoleId, caller address) CanCallResult {
	adminRole := state.GetRoleAdmin(role)
	membership := state.HasRole(adminRole, caller)
	if !membership.IsMember {
		return NewCanCallResult(false, 0)
	}
	return NewCanCallResult(membership.ExecutionDelay == 0, membership.ExecutionDelay)
}

func (state *State) CanManageTarget(caller address) CanCallResult {
	membership := state.HasRole(AdminRole, caller)
	if !membership.IsMember {
		return NewCanCallResult(false, 0)
	}
	return NewCanCallResult(membership.ExecutionDelay == 0, membership.ExecutionDelay)
}

func (state *State) getRole(role RoleId) *RoleConfig {
	state.ensureInitialized()
	return state.Roles[role]
}

func (state *State) ensureRole(role RoleId) *RoleConfig {
	state.ensureInitialized()
	roleConfig := state.Roles[role]
	if roleConfig == nil {
		roleConfig = NewRoleConfig(AdminRole, 0, 0)
		state.Roles[role] = roleConfig
	}
	return roleConfig
}

func (state *State) getTarget(target string) *TargetConfig {
	state.ensureInitialized()
	return state.Targets[target]
}

func (state *State) ensureTarget(target string) *TargetConfig {
	state.ensureInitialized()
	targetConfig := state.Targets[target]
	if targetConfig == nil {
		targetConfig = NewTargetConfig(0, false)
		state.Targets[target] = targetConfig
	}
	return targetConfig
}

func (state *State) ensureInitialized() {
	if state.Roles == nil {
		state.Roles = make(map[RoleId]*RoleConfig)
	}
	if state.Targets == nil {
		state.Targets = make(map[string]*TargetConfig)
	}
}

func requireUnlockedConfigRole(role RoleId) {
	if role == AdminRole || role == PublicRole {
		panic(AccessManagerLockedRoleError(role))
	}
}
