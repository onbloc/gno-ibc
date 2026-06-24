package manager

import "strconv"

type RoleId uint64

func NewRoleId(id uint64) RoleId {
	return RoleId(id)
}

func (r RoleId) Uint64() uint64 {
	return uint64(r)
}

func (r RoleId) String() string {
	return strconv.FormatUint(uint64(r), 10)
}

type RoleConfig struct {
	Members    map[address]Access
	Admin      RoleId
	Guardian   RoleId
	GrantDelay DelayedValue
}

func NewRoleConfig(admin RoleId, grantDelay Delay) *RoleConfig {
	return &RoleConfig{
		Members:    make(map[address]Access),
		Admin:      admin,
		Guardian:   AdminRole,
		GrantDelay: NewDelayedValue(grantDelay),
	}
}

func (roleConfig *RoleConfig) grant(account address, now TimePoint, executionDelay Delay) bool {
	newMember, _ := roleConfig.grantWithEffect(account, now, executionDelay)

	return newMember
}

func (roleConfig *RoleConfig) grantWithEffect(account address, now TimePoint, executionDelay Delay) (bool, TimePoint) {
	access, found := roleConfig.Members[account]
	if found {
		updatedAccess, effect := access.withExecutionDelayUpdate(now, executionDelay)
		roleConfig.Members[account] = updatedAccess

		return false, effect
	}

	access = NewAccessWithDelay(now, roleConfig.grantDelayAt(now), executionDelay)
	roleConfig.Members[account] = access

	return true, access.Since
}

func (roleConfig *RoleConfig) revoke(account address) bool {
	_, found := roleConfig.Members[account]
	if found {
		delete(roleConfig.Members, account)
	}

	return found
}

func (roleConfig *RoleConfig) hasMember(account address, now TimePoint) bool {
	access, found := roleConfig.Members[account]
	if !found {
		return false
	}

	return access.isActiveAt(now)
}

func (roleConfig *RoleConfig) access(account address, now TimePoint) Access {
	access, found := roleConfig.Members[account]
	if !found || !access.isActiveAt(now) {
		return Access{}
	}

	return access
}

func (roleConfig *RoleConfig) rawAccess(account address) Access {
	return roleConfig.Members[account]
}

func (roleConfig *RoleConfig) setAdmin(admin RoleId) {
	roleConfig.Admin = admin
}

func (roleConfig *RoleConfig) adminRole() RoleId {
	return roleConfig.Admin
}

func (roleConfig *RoleConfig) setGuardian(guardian RoleId) {
	roleConfig.Guardian = guardian
}

func (roleConfig *RoleConfig) guardianRole() RoleId {
	return roleConfig.Guardian
}

func (roleConfig *RoleConfig) setGrantDelay(delay Delay, now TimePoint) TimePoint {
	grantDelay, effect := roleConfig.GrantDelay.WithUpdate(now, delay, MinSetback)
	roleConfig.GrantDelay = grantDelay

	return effect
}

func (roleConfig *RoleConfig) grantDelayAt(now TimePoint) Delay {
	return roleConfig.GrantDelay.Get(now)
}

func (roleConfig *RoleConfig) grantDelay() Delay {
	return roleConfig.grantDelayAt(CurrentTimePoint())
}
