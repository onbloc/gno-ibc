package manager

func (roleConfig *RoleConfig) grant(account address, now Timepoint) bool {
	roleConfig.ensureMembers()
	_, found := roleConfig.Members[account]
	if found {
		return false
	}
	roleConfig.Members[account] = NewAccess(timepointAvailableAt(now, roleConfig.GrantDelay))
	return true
}

func (roleConfig *RoleConfig) revoke(account address) bool {
	roleConfig.ensureMembers()
	_, found := roleConfig.Members[account]
	if found {
		delete(roleConfig.Members, account)
	}
	return found
}

func (roleConfig *RoleConfig) hasMember(account address, now Timepoint) bool {
	roleConfig.ensureMembers()
	access, found := roleConfig.Members[account]
	if !found {
		return false
	}
	return access.isActiveAt(now)
}

func (roleConfig *RoleConfig) setAdmin(admin RoleId) {
	roleConfig.Admin = admin
}

func (roleConfig *RoleConfig) adminRole() RoleId {
	return roleConfig.Admin
}

func (roleConfig *RoleConfig) setGrantDelay(delay Delay) {
	roleConfig.GrantDelay = delay
}

func (roleConfig *RoleConfig) grantDelay() Delay {
	return roleConfig.GrantDelay
}

func (roleConfig *RoleConfig) ensureMembers() {
	if roleConfig.Members == nil {
		roleConfig.Members = make(map[address]Access)
	}
}
