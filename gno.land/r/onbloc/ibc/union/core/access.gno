package core

import (
	manager "gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// RelayerRole mirrors Union deployer's RELAYER role id.
// Reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L65
const RelayerRole manager.RoleId = access.RelayerRole

const (
	SelectorForceUpdateClient        manager.Selector = "force_update_client"
	SelectorForceConnectionTry       manager.Selector = "force_connection_open_try"
	SelectorForceConnectionAck       manager.Selector = "force_connection_open_ack"
	SelectorForceConnectionConfirm   manager.Selector = "force_connection_open_confirm"
	SelectorForceChannelTry          manager.Selector = "force_channel_open_try"
	SelectorForceChannelAck          manager.Selector = "force_channel_open_ack"
	SelectorForceChannelConfirm      manager.Selector = "force_channel_open_confirm"
	SelectorChannelCloseInit         manager.Selector = "channel_close_init"
	SelectorChannelCloseConfirm      manager.Selector = "channel_close_confirm"
	SelectorCommitMembershipProof    manager.Selector = "commit_membership_proof"
	SelectorCommitNonMembershipProof manager.Selector = "commit_non_membership_proof"
	SelectorRegisterPort             manager.Selector = "register_port"
)

const (
	SelectorRegisterClient        manager.Selector = types.RelayerSelectorRegisterClient
	SelectorCreateClient          manager.Selector = types.RelayerSelectorCreateClient
	SelectorUpdateClient          manager.Selector = types.RelayerSelectorUpdateClient
	SelectorConnectionOpenInit    manager.Selector = types.RelayerSelectorConnectionOpenInit
	SelectorConnectionOpenTry     manager.Selector = types.RelayerSelectorConnectionOpenTry
	SelectorConnectionOpenAck     manager.Selector = types.RelayerSelectorConnectionOpenAck
	SelectorConnectionOpenConfirm manager.Selector = types.RelayerSelectorConnectionOpenConfirm
	SelectorChannelOpenInit       manager.Selector = types.RelayerSelectorChannelOpenInit
	SelectorChannelOpenTry        manager.Selector = types.RelayerSelectorChannelOpenTry
	SelectorChannelOpenAck        manager.Selector = types.RelayerSelectorChannelOpenAck
	SelectorChannelOpenConfirm    manager.Selector = types.RelayerSelectorChannelOpenConfirm
	SelectorPacketRecv            manager.Selector = types.RelayerSelectorPacketRecv
	SelectorIntentPacketRecv      manager.Selector = types.RelayerSelectorIntentPacketRecv
	SelectorPacketAck             manager.Selector = types.RelayerSelectorPacketAck
	SelectorPacketTimeout         manager.Selector = types.RelayerSelectorPacketTimeout
	SelectorBatchSend             manager.Selector = types.RelayerSelectorBatchSend
	SelectorBatchAcks             manager.Selector = types.RelayerSelectorBatchAcks
)
