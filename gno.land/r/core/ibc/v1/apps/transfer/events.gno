package transfer

// IBC transfer events
const (
	EventTypeTimeout  = "timeout"
	EventTypePacket   = "fungible_token_packet"
	EventTypeTransfer = "ibc_transfer"
	EventTypeDenom    = "denomination"
	EventTypeHookSet  = "transfer_hook_set"
	EventTypeHookExec = "transfer_hook_exec"

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
	AttributeKeyHookCaller     = "hook_caller"
)
