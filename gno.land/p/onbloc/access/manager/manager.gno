package manager

// GrantRole grants role membership to account and returns true for a new member.
// This Gno port retains grant delay but intentionally omits OZ execution delay.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L233-L236
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L271-L298
func (state *State) GrantRole(role RoleId, account address) bool {
	if role == PublicRole {
		panic(AccessManagerLockedRoleError(role))
	}
	roleConfig := state.ensureRole(role)
	_, found := roleConfig.Members[account]
	if found {
		return false
	}
	roleConfig.Members[account] = NewAccess(timepointAvailableAt(CurrentTimepoint(), roleConfig.GrantDelay))
	return true
}

// RevokeRole revokes role membership from account and reports whether it existed.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L238-L240
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L300-L319
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

// RenounceRole revokes caller-confirmed role membership from account.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L243-L249
func (state *State) RenounceRole(role RoleId, account address, callerConfirmation address) bool {
	if account != callerConfirmation {
		panic(ErrorAccessManagerBadConfirmation)
	}
	return state.RevokeRole(role, account)
}

// HasRole reports whether account currently has an active role membership.
// This Gno port returns membership only because execution delay is not ported.
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
	access, found := roleConfig.Members[account]
	if !found || access.Since.IsZero() {
		return NewHasRoleResult(false)
	}
	if access.Since.After(CurrentTimepoint()) {
		return NewHasRoleResult(false)
	}
	return NewHasRoleResult(true)
}

// SetRoleAdmin sets the admin role that can grant or revoke role.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L251-L254
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L321-L337
func (state *State) SetRoleAdmin(role RoleId, admin RoleId) {
	RequireUnlockedConfigRole(role)
	state.ensureRole(role).Admin = admin
}

// GetRoleAdmin returns the admin role for role, defaulting to AdminRole.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L183-L186
func (state *State) GetRoleAdmin(role RoleId) RoleId {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return AdminRole
	}
	return roleConfig.Admin
}

// SetGrantDelay sets the delay before future grants of role become active.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L261-L264
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L357-L371
func (state *State) SetGrantDelay(role RoleId, delay Delay) {
	if role == PublicRole {
		panic(AccessManagerLockedRoleError(role))
	}
	state.ensureRole(role).GrantDelay = delay
}

// GetRoleGrantDelay returns the grant delay configured for role.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L193-L196
func (state *State) GetRoleGrantDelay(role RoleId) Delay {
	roleConfig := state.getRole(role)
	if roleConfig == nil {
		return 0
	}
	return roleConfig.GrantDelay
}

// SetTargetFunctionRole sets the role required for target selector.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L385-L393
func (state *State) SetTargetFunctionRole(target string, selector Selector, role RoleId) {
	state.ensureTarget(target).FunctionRoles[selector] = role
}

// SetTargetFunctionRoles sets the same role for multiple target selectors.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L373-L383
func (state *State) SetTargetFunctionRoles(target string, selectors []Selector, role RoleId) {
	for i := range selectors {
		state.SetTargetFunctionRole(target, selectors[i], role)
	}
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
	role, found := targetConfig.FunctionRoles[selector]
	if !found {
		return AdminRole
	}
	return role
}

// SetTargetClosed sets whether target rejects calls regardless of selector role.
// OpenZeppelin references:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L412-L416
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L418-L426
func (state *State) SetTargetClosed(target string, closed bool) {
	state.ensureTarget(target).Closed = closed
}

// IsTargetClosed reports whether target is closed.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L168-L171
func (state *State) IsTargetClosed(target string) bool {
	targetConfig := state.getTarget(target)
	return targetConfig != nil && targetConfig.Closed
}

// CanCall reports whether caller can call target selector immediately.
// This Gno port returns only immediate authorization because scheduled
// execution and execution delay are intentionally not ported.
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
	return NewCanCallResult(true)
}

// IsAuthorized is a boolean convenience wrapper around CanCall.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L140-L156
func (state *State) IsAuthorized(caller address, target string, selector Selector) bool {
	return state.CanCall(caller, target, selector).Immediate
}

// CanAdminRole reports whether caller has the admin role required for role.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L652-L657
func (state *State) CanAdminRole(role RoleId, caller address) CanCallResult {
	adminRole := state.GetRoleAdmin(role)
	membership := state.HasRole(adminRole, caller)
	if !membership.IsMember {
		return NewCanCallResult(false)
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
	return NewCanCallResult(true)
}

func (state *State) getRole(role RoleId) *RoleConfig {
	state.ensureInitialized()
	return state.Roles[role]
}

func (state *State) ensureRole(role RoleId) *RoleConfig {
	state.ensureInitialized()
	roleConfig := state.Roles[role]
	if roleConfig == nil {
		roleConfig = NewRoleConfig(AdminRole, 0)
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
		targetConfig = NewTargetConfig(false)
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

// RequireUnlockedConfigRole rejects role ids whose configuration is locked.
// Use this before emitting LabelRole metadata from a realm.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L226-L230
func RequireUnlockedConfigRole(role RoleId) {
	if role == AdminRole || role == PublicRole {
		panic(AccessManagerLockedRoleError(role))
	}
}
