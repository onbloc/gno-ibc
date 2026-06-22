package core

import (
	manager "gno.land/p/onbloc/access/manager"
	"gno.land/r/onbloc/ibc/union/access"
)

// RelayerRole mirrors Union deployer's RELAYER role id.
// Reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65
const RelayerRole manager.RoleId = access.RelayerRole

const (
	SelectorRegisterClient           manager.Selector = "register_client"
	SelectorCreateClient             manager.Selector = "create_client"
	SelectorUpdateClient             manager.Selector = "update_client"
	SelectorForceUpdateClient        manager.Selector = "force_update_client"
	SelectorConnectionOpenInit       manager.Selector = "connection_open_init"
	SelectorConnectionOpenTry        manager.Selector = "connection_open_try"
	SelectorConnectionOpenAck        manager.Selector = "connection_open_ack"
	SelectorConnectionOpenConfirm    manager.Selector = "connection_open_confirm"
	SelectorForceConnectionTry       manager.Selector = "force_connection_open_try"
	SelectorForceConnectionAck       manager.Selector = "force_connection_open_ack"
	SelectorForceConnectionConfirm   manager.Selector = "force_connection_open_confirm"
	SelectorChannelOpenInit          manager.Selector = "channel_open_init"
	SelectorChannelOpenTry           manager.Selector = "channel_open_try"
	SelectorChannelOpenAck           manager.Selector = "channel_open_ack"
	SelectorChannelOpenConfirm       manager.Selector = "channel_open_confirm"
	SelectorForceChannelTry          manager.Selector = "force_channel_open_try"
	SelectorForceChannelAck          manager.Selector = "force_channel_open_ack"
	SelectorForceChannelConfirm      manager.Selector = "force_channel_open_confirm"
	SelectorChannelCloseInit         manager.Selector = "channel_close_init"
	SelectorChannelCloseConfirm      manager.Selector = "channel_close_confirm"
	SelectorPacketRecv               manager.Selector = "packet_recv"
	SelectorIntentPacketRecv         manager.Selector = "intent_packet_recv"
	SelectorPacketAck                manager.Selector = "packet_ack"
	SelectorPacketTimeout            manager.Selector = "packet_timeout"
	SelectorCommitMembershipProof    manager.Selector = "commit_membership_proof"
	SelectorCommitNonMembershipProof manager.Selector = "commit_non_membership_proof"
	SelectorBatchSend                manager.Selector = "batch_send"
	SelectorBatchAcks                manager.Selector = "batch_acks"
	SelectorRegisterPort             manager.Selector = "register_port"
)
