package manager

import "strconv"

const (
	ErrorAccessManagerLockedRole      = "AccessManagerLockedRole"
	ErrorAccessManagerBadConfirmation = "AccessManagerBadConfirmation: confirmation address does not match sender"
)

// AccessManagerLockedRoleError formats a locked-role error for role.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L226-L230
func AccessManagerLockedRoleError(role RoleId) string {
	return ErrorAccessManagerLockedRole + ": role " + strconv.FormatUint(uint64(role), 10) + " is locked"
}
