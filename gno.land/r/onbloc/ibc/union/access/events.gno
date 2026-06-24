package access

import (
	"chain"
	"strconv"

	"gno.land/p/onbloc/access/manager"
)

func emitRoleLabelEvent(role manager.RoleId, label string) {
	chain.Emit(
		manager.EventTypeRoleLabel,
		manager.AttributeKeyRoleID, role.String(),
		manager.AttributeKeyLabel, label,
	)
}

func emitRoleGrantedEvent(role manager.RoleId, account address, since manager.TimePoint, delay manager.Delay, newMember bool) {
	chain.Emit(
		manager.EventTypeRoleGranted,
		manager.AttributeKeyRoleID, role.String(),
		manager.AttributeKeyAccount, account.String(),
		manager.AttributeKeySince, since.String(),
		manager.AttributeKeyDelay, delay.String(),
		manager.AttributeKeyNewMember, strconv.FormatBool(newMember),
	)
}

func emitRoleRevokedEvent(role manager.RoleId, account address) {
	chain.Emit(
		manager.EventTypeRoleRevoked,
		manager.AttributeKeyRoleID, role.String(),
		manager.AttributeKeyAccount, account.String(),
	)
}

func emitRoleAdminChangedEvent(role manager.RoleId, admin manager.RoleId) {
	chain.Emit(
		manager.EventTypeRoleAdminChanged,
		manager.AttributeKeyRoleID, role.String(),
		manager.AttributeKeyAdmin, admin.String(),
	)
}

func emitRoleGuardianChangedEvent(role manager.RoleId, guardian manager.RoleId) {
	chain.Emit(
		manager.EventTypeRoleGuardianChanged,
		manager.AttributeKeyRoleID, role.String(),
		manager.AttributeKeyGuardian, guardian.String(),
	)
}

func emitRoleGrantDelayChangedEvent(role manager.RoleId, delay manager.Delay, since manager.TimePoint) {
	chain.Emit(
		manager.EventTypeRoleGrantDelayChanged,
		manager.AttributeKeyRoleID, role.String(),
		manager.AttributeKeyDelay, delay.String(),
		manager.AttributeKeySince, since.String(),
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
		manager.AttributeKeyRoleID, role.String(),
	)
}

func emitTargetAdminDelayUpdatedEvent(target string, delay manager.Delay, since manager.TimePoint) {
	chain.Emit(
		manager.EventTypeTargetAdminDelayUpdated,
		manager.AttributeKeyTarget, target,
		manager.AttributeKeyDelay, delay.String(),
		manager.AttributeKeySince, since.String(),
	)
}

func emitOperationScheduledEvent(
	operationId manager.OperationId,
	caller address,
	target string,
	selector manager.Selector,
	dataHash string,
	when manager.TimePoint,
	nonce manager.Nonce,
) {
	chain.Emit(
		manager.EventTypeOperationScheduled,
		manager.AttributeKeyOperationID, operationId.String(),
		manager.AttributeKeyCaller, caller.String(),
		manager.AttributeKeyTarget, target,
		manager.AttributeKeySelector, string(selector),
		manager.AttributeKeyDataHash, dataHash,
		manager.AttributeKeyWhen, when.String(),
		manager.AttributeKeyNonce, nonce.String(),
	)
}

func emitOperationExecutedEvent(
	operationId manager.OperationId,
	caller address,
	target string,
	selector manager.Selector,
	dataHash string,
	nonce manager.Nonce,
) {
	chain.Emit(
		manager.EventTypeOperationExecuted,
		manager.AttributeKeyOperationID, operationId.String(),
		manager.AttributeKeyCaller, caller.String(),
		manager.AttributeKeyTarget, target,
		manager.AttributeKeySelector, string(selector),
		manager.AttributeKeyDataHash, dataHash,
		manager.AttributeKeyNonce, nonce.String(),
	)
}

func emitOperationCanceledEvent(
	operationId manager.OperationId,
	caller address,
	target string,
	selector manager.Selector,
	dataHash string,
	nonce manager.Nonce,
) {
	chain.Emit(
		manager.EventTypeOperationCanceled,
		manager.AttributeKeyOperationID, operationId.String(),
		manager.AttributeKeyCaller, caller.String(),
		manager.AttributeKeyTarget, target,
		manager.AttributeKeySelector, string(selector),
		manager.AttributeKeyDataHash, dataHash,
		manager.AttributeKeyNonce, nonce.String(),
	)
}
