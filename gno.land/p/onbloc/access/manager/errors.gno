package manager

import "strconv"

const (
	ErrorAccessManagerLockedRole      = "AccessManagerLockedRole"
	ErrorAccessManagerBadConfirmation = "AccessManagerBadConfirmation: confirmation address does not match sender"
)

func AccessManagerLockedRoleError(role RoleId) string {
	return ErrorAccessManagerLockedRole + ": role " + strconv.FormatUint(uint64(role), 10) + " is locked"
}
