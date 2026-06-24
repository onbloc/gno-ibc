package manager

const (
	EventTypeRoleLabel                 = "RoleLabel"
	EventTypeRoleGranted               = "RoleGranted"
	EventTypeRoleRevoked               = "RoleRevoked"
	EventTypeRoleAdminChanged          = "RoleAdminChanged"
	EventTypeRoleGuardianChanged       = "RoleGuardianChanged"
	EventTypeRoleGrantDelayChanged     = "RoleGrantDelayChanged"
	EventTypeTargetClosed              = "TargetClosed"
	EventTypeTargetAdminDelayUpdated   = "TargetAdminDelayUpdated"
	EventTypeTargetFunctionRoleUpdated = "TargetFunctionRoleUpdated"
	EventTypeOperationScheduled        = "OperationScheduled"
	EventTypeOperationExecuted         = "OperationExecuted"
	EventTypeOperationCanceled         = "OperationCanceled"
)

const (
	AttributeKeyTarget      = "target"
	AttributeKeyRoleID      = "role_id"
	AttributeKeyLabel       = "label"
	AttributeKeyAccount     = "account"
	AttributeKeyDelay       = "delay"
	AttributeKeySince       = "since"
	AttributeKeyNewMember   = "new_member"
	AttributeKeyAdmin       = "admin"
	AttributeKeyGuardian    = "guardian"
	AttributeKeyClosed      = "closed"
	AttributeKeySelector    = "selector"
	AttributeKeyOperationID = "operation_id"
	AttributeKeyCaller      = "caller"
	AttributeKeyDataHash    = "data_hash"
	AttributeKeyWhen        = "when"
	AttributeKeyNonce       = "nonce"
)
