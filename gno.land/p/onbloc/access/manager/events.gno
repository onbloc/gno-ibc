package manager

const (
	EventTypeOperationScheduled         = "OperationScheduled"
	EventTypeOperationExecuted          = "OperationExecuted"
	EventTypeOperationCanceled          = "OperationCanceled"
	EventTypeRoleLabel                  = "RoleLabel"
	EventTypeRoleGranted                = "RoleGranted"
	EventTypeRoleRevoked                = "RoleRevoked"
	EventTypeRoleAdminChanged           = "RoleAdminChanged"
	EventTypeRoleGrantDelayChanged      = "RoleGrantDelayChanged"
	EventTypeTargetClosed               = "TargetClosed"
	EventTypeTargetFunctionRoleUpdated  = "TargetFunctionRoleUpdated"
	EventTypeTargetAdminDelayUpdated    = "TargetAdminDelayUpdated"
)

const (
	AttributeKeyOperationID = "operation_id"
	AttributeKeyNonce       = "nonce"
	AttributeKeySchedule    = "schedule"
	AttributeKeyCaller      = "caller"
	AttributeKeyTarget      = "target"
	AttributeKeyData        = "data"
	AttributeKeyRoleID      = "role_id"
	AttributeKeyLabel       = "label"
	AttributeKeyAccount     = "account"
	AttributeKeyDelay       = "delay"
	AttributeKeySince       = "since"
	AttributeKeyNewMember   = "new_member"
	AttributeKeyAdmin       = "admin"
	AttributeKeyClosed      = "closed"
	AttributeKeySelector    = "selector"
)
