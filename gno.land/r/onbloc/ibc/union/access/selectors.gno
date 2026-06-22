package access

import manager "gno.land/p/onbloc/access/manager"

const (
	SelectorGrantRole             manager.Selector = "grant_role"
	SelectorRevokeRole            manager.Selector = "revoke_role"
	SelectorSetTargetFunctionRole manager.Selector = "set_target_function_role"
	SelectorCreateClient          manager.Selector = "create_client"
	SelectorUpdateClient          manager.Selector = "update_client"
	SelectorConnectionOpenInit    manager.Selector = "connection_open_init"
	SelectorConnectionOpenTry     manager.Selector = "connection_open_try"
	SelectorConnectionOpenAck     manager.Selector = "connection_open_ack"
	SelectorConnectionOpenConfirm manager.Selector = "connection_open_confirm"
	SelectorChannelOpenInit       manager.Selector = "channel_open_init"
	SelectorChannelOpenTry        manager.Selector = "channel_open_try"
	SelectorChannelOpenAck        manager.Selector = "channel_open_ack"
	SelectorChannelOpenConfirm    manager.Selector = "channel_open_confirm"
	SelectorPacketRecv            manager.Selector = "packet_recv"
	SelectorIntentPacketRecv      manager.Selector = "intent_packet_recv"
	SelectorPacketAck             manager.Selector = "packet_ack"
	SelectorPacketTimeout         manager.Selector = "packet_timeout"
	SelectorBatchSend             manager.Selector = "batch_send"
	SelectorBatchAcks             manager.Selector = "batch_acks"
)
