package access

import (
	"chain"
	"strconv"

	manager "gno.land/p/onbloc/access/manager"
)

func emitRoleLabelEvent(role manager.RoleId, label string) {
	chain.Emit(
		manager.EventTypeRoleLabel,
		manager.AttributeKeyRoleID, formatRoleID(role),
		manager.AttributeKeyLabel, label,
	)
}

func emitRoleGrantedEvent(role manager.RoleId, account address, delay manager.Delay, since manager.Timepoint, newMember bool) {
	chain.Emit(
		manager.EventTypeRoleGranted,
		manager.AttributeKeyRoleID, formatRoleID(role),
		manager.AttributeKeyAccount, account.String(),
		manager.AttributeKeyDelay, formatDelay(delay),
		manager.AttributeKeySince, formatTimepoint(since),
		manager.AttributeKeyNewMember, strconv.FormatBool(newMember),
	)
}

func emitRoleRevokedEvent(role manager.RoleId, account address) {
	chain.Emit(
		manager.EventTypeRoleRevoked,
		manager.AttributeKeyRoleID, formatRoleID(role),
		manager.AttributeKeyAccount, account.String(),
	)
}

func emitRoleAdminChangedEvent(role manager.RoleId, admin manager.RoleId) {
	chain.Emit(
		manager.EventTypeRoleAdminChanged,
		manager.AttributeKeyRoleID, formatRoleID(role),
		manager.AttributeKeyAdmin, formatRoleID(admin),
	)
}

func emitRoleGrantDelayChangedEvent(role manager.RoleId, delay manager.Delay, since manager.Timepoint) {
	chain.Emit(
		manager.EventTypeRoleGrantDelayChanged,
		manager.AttributeKeyRoleID, formatRoleID(role),
		manager.AttributeKeyDelay, formatDelay(delay),
		manager.AttributeKeySince, formatTimepoint(since),
	)
}

func emitTargetClosedEvent(target string, closed bool) {
	chain.Emit(
		manager.EventTypeTargetClosed,
		manager.AttributeKeyTarget, target,
		manager.AttributeKeyClosed, strconv.FormatBool(closed),
	)
}

func emitTargetFunctionRoleUpdatedEvent(target string, selector manager.Selector, role manager.RoleId) {
	chain.Emit(
		manager.EventTypeTargetFunctionRoleUpdated,
		manager.AttributeKeyTarget, target,
		manager.AttributeKeySelector, string(selector),
		manager.AttributeKeyRoleID, formatRoleID(role),
	)
}

func emitTargetAdminDelayUpdatedEvent(target string, delay manager.Delay, since manager.Timepoint) {
	chain.Emit(
		manager.EventTypeTargetAdminDelayUpdated,
		manager.AttributeKeyTarget, target,
		manager.AttributeKeyDelay, formatDelay(delay),
		manager.AttributeKeySince, formatTimepoint(since),
	)
}

func formatRoleID(role manager.RoleId) string {
	return strconv.FormatUint(uint64(role), 10)
}

func formatDelay(delay manager.Delay) string {
	return strconv.FormatUint(uint64(delay), 10)
}

func formatTimepoint(timepoint manager.Timepoint) string {
	return strconv.FormatInt(int64(timepoint), 10)
}
