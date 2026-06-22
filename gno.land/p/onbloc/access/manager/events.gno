package manager

import (
	"chain"
	"strconv"
)

const RoleLabelEvent = "RoleLabel"

func emitRoleLabelEvent(role RoleId, label string) {
	chain.Emit(
		RoleLabelEvent,
		"role_id", strconv.FormatUint(uint64(role), 10),
		"label", label,
	)
}
