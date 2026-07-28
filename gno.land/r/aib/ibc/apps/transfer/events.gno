package transfer

// IBC transfer events
const (
	EventTypeTimeout             = "timeout"
	EventTypePacket              = "fungible_token_packet"
	EventTypeTransfer            = "ibc_transfer"
	EventTypeDenom               = "denomination"
	EventTypeSendResultDelivered = "send_result_delivered"

	AttributeKeySender         = "sender"
	AttributeKeyReceiver       = "receiver"
	AttributeKeyDenom          = "denom"
	AttributeKeyDenomHash      = "denom_hash"
	AttributeKeyAmount         = "amount"
	AttributeKeyRefundReceiver = "refund_receiver"
	AttributeKeyRefundTokens   = "refund_tokens"
	AttributeKeyAckSuccess     = "success"
	AttributeKeyAck            = "acknowledgement"
	AttributeKeyAckError       = "error"
	AttributeKeyMemo           = "memo"
	AttributeKeyCallerPkgPath  = "caller_pkg_path"
	AttributeKeyCorrID         = "corr_id"
)
