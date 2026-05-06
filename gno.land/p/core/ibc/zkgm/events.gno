package zkgm

const (
	EventTypeForwardChildAck     = "zkgm_forward_child_ack"
	EventTypeForwardChildTimeout = "zkgm_forward_child_timeout"

	AttributeKeyParentSequence = "parent_sequence"
	AttributeKeyChildSequence  = "child_sequence"
	AttributeKeyParentClient   = "parent_client"
	AttributeKeyChildClient    = "child_client"
	AttributeKeyAckHex         = "ack_hex"
)
