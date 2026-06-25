package core

import (
	"chain"
	"strconv"

	"gno.land/p/onbloc/ibc/union/types"
)

const (
	AppRegisteredEvent         = "AppRegistered"
	RegisterClientEvent        = "RegisterClient"
	CreateClientEvent          = "CreateClient"
	UpdateClientEvent          = "UpdateClient"
	ForceUpdateClientEvent     = "ForceUpdateClient"
	MisbehaviourEvent          = "Misbehaviour"
	ConnectionOpenInitEvent    = "ConnectionOpenInit"
	ConnectionOpenTryEvent     = "ConnectionOpenTry"
	ConnectionOpenAckEvent     = "ConnectionOpenAck"
	ConnectionOpenConfirmEvent = "ConnectionOpenConfirm"
	ChannelOpenInitEvent       = "ChannelOpenInit"
	ChannelOpenTryEvent        = "ChannelOpenTry"
	ChannelOpenAckEvent        = "ChannelOpenAck"
	ChannelOpenConfirmEvent    = "ChannelOpenConfirm"
	ChannelCloseInitEvent      = "ChannelCloseInit"
	ChannelCloseConfirmEvent   = "ChannelCloseConfirm"
	PacketSendEvent            = "PacketSend"
	BatchSendEvent             = "BatchSend"
	BatchAcksEvent             = "BatchAcks"
	PacketRecvEvent            = "PacketRecv"
	IntentPacketRecvEvent      = "IntentPacketRecv"
	WriteAckEvent              = "WriteAck"
	PacketAckEvent             = "PacketAck"
	PacketTimeoutEvent         = "PacketTimeout"
	CommitMembershipProofEvent = "CommitMembershipProof"
	CommitNonMembershipEvent   = "CommitNonMembershipProof"

	maxEventAttrValueLen      = 1024
	maxPacketDataEventColumns = 50
	MaxPacketDataEventSize    = maxPacketDataEventColumns * maxEventAttrValueLen
)

func channelOpenInitEventAttrs(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) []string {
	return []string{
		"port_id", string(portId),
		"channel_id", channelId.String(),
		"counterparty_port_id", channel.CounterpartyPortId.String(),
		"connection_id", channel.ConnectionId.String(),
		"connection_client_id", connection.ClientId.String(),
		"connection_counterparty_client_id", connection.CounterpartyClientId.String(),
		"connection_counterparty_connection_id", connection.CounterpartyConnectionId.String(),
		"version", channel.Version,
	}
}

func channelOpenTryEventAttrs(portId types.Bytes, channelId types.ChannelId, channel types.Channel, counterpartyVersion string, connection types.Connection) []string {
	return []string{
		"port_id", string(portId),
		"channel_id", channelId.String(),
		"counterparty_port_id", channel.CounterpartyPortId.String(),
		"counterparty_channel_id", channel.CounterpartyChannelId.String(),
		"connection_id", channel.ConnectionId.String(),
		"connection_client_id", connection.ClientId.String(),
		"connection_counterparty_client_id", connection.CounterpartyClientId.String(),
		"connection_counterparty_connection_id", connection.CounterpartyConnectionId.String(),
		"version", channel.Version,
		"counterparty_version", counterpartyVersion,
	}
}

func channelOpenAckConfirmEventAttrs(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) []string {
	return []string{
		"port_id", string(portId),
		"channel_id", channelId.String(),
		"counterparty_port_id", channel.CounterpartyPortId.String(),
		"counterparty_channel_id", channel.CounterpartyChannelId.String(),
		"connection_id", channel.ConnectionId.String(),
		"connection_client_id", connection.ClientId.String(),
		"connection_counterparty_client_id", connection.CounterpartyClientId.String(),
		"connection_counterparty_connection_id", connection.CounterpartyConnectionId.String(),
		"version", channel.Version,
	}
}

func channelCloseEventAttrs(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) []string {
	return []string{
		"port_id", string(portId),
		"channel_id", channelId.String(),
		"counterparty_port_id", channel.CounterpartyPortId.String(),
		"counterparty_channel_id", channel.CounterpartyChannelId.String(),
		"connection_id", channel.ConnectionId.String(),
		"connection_client_id", connection.ClientId.String(),
		"connection_counterparty_client_id", connection.CounterpartyClientId.String(),
		"connection_counterparty_connection_id", connection.CounterpartyConnectionId.String(),
		"version", channel.Version,
	}
}

func emitChannelOpenInitEvent(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) {
	chain.Emit(ChannelOpenInitEvent, channelOpenInitEventAttrs(portId, channelId, channel, connection)...)
}

func emitChannelOpenTryEvent(portId types.Bytes, channelId types.ChannelId, channel types.Channel, counterpartyVersion string, connection types.Connection) {
	chain.Emit(ChannelOpenTryEvent, channelOpenTryEventAttrs(portId, channelId, channel, counterpartyVersion, connection)...)
}

func emitChannelOpenAckEvent(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) {
	chain.Emit(ChannelOpenAckEvent, channelOpenAckConfirmEventAttrs(portId, channelId, channel, connection)...)
}

func emitChannelOpenConfirmEvent(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) {
	chain.Emit(ChannelOpenConfirmEvent, channelOpenAckConfirmEventAttrs(portId, channelId, channel, connection)...)
}

func emitChannelCloseInitEvent(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) {
	chain.Emit(ChannelCloseInitEvent, channelCloseEventAttrs(portId, channelId, channel, connection)...)
}

func emitChannelCloseConfirmEvent(portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) {
	chain.Emit(ChannelCloseConfirmEvent, channelCloseEventAttrs(portId, channelId, channel, connection)...)
}

func emitConnectionOpenInitEvent(connectionId types.ConnectionId, clientId types.ClientId, counterpartyClientId types.ClientId) {
	chain.Emit(
		ConnectionOpenInitEvent,
		"connection_id", connectionId.String(),
		"client_id", clientId.String(),
		"counterparty_client_id", counterpartyClientId.String(),
	)
}

func emitConnectionOpenTryEvent(connectionId types.ConnectionId, clientId types.ClientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) {
	chain.Emit(ConnectionOpenTryEvent, connectionOpenEventAttrs(connectionId, clientId, counterpartyClientId, counterpartyConnectionId)...)
}

func emitConnectionOpenAckEvent(connectionId types.ConnectionId, clientId types.ClientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) {
	chain.Emit(ConnectionOpenAckEvent, connectionOpenEventAttrs(connectionId, clientId, counterpartyClientId, counterpartyConnectionId)...)
}

func emitConnectionOpenConfirmEvent(connectionId types.ConnectionId, clientId types.ClientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) {
	chain.Emit(ConnectionOpenConfirmEvent, connectionOpenEventAttrs(connectionId, clientId, counterpartyClientId, counterpartyConnectionId)...)
}

func connectionOpenEventAttrs(connectionId types.ConnectionId, clientId types.ClientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) []string {
	return []string{
		"connection_id", connectionId.String(),
		"client_id", clientId.String(),
		"counterparty_client_id", counterpartyClientId.String(),
		"counterparty_connection_id", counterpartyConnectionId.String(),
	}
}

func emitRegisterClientEvent(clientType types.ClientType) {
	chain.Emit(
		RegisterClientEvent,
		"client_type", clientType.String(),
	)
}

func emitCreateClientEvent(clientId types.ClientId, clientType types.ClientType, counterpartyChainId string) {
	chain.Emit(
		CreateClientEvent,
		"client_id", clientId.String(),
		"client_type", clientType.String(),
		"counterparty_chain_id", counterpartyChainId,
	)
}

func emitUpdateClientEvent(clientId types.ClientId, height types.Height) {
	chain.Emit(
		UpdateClientEvent,
		"client_id", clientId.String(),
		"height", height.String(),
	)
}

func emitForceUpdateClientEvent(clientId types.ClientId, height types.Height) {
	chain.Emit(
		ForceUpdateClientEvent,
		"client_id", clientId.String(),
		"height", height.String(),
	)
}

func emitMisbehaviourEvent(clientId types.ClientId) {
	chain.Emit(
		MisbehaviourEvent,
		"client_id", clientId.String(),
	)
}

func emitAppRegisteredEvent(portId []byte, registrarPkgPath string, adminOverride bool) {
	chain.Emit(
		AppRegisteredEvent,
		"port_id", string(portId),
		"registrar_pkg_path", registrarPkgPath,
		"admin_override", strconv.FormatBool(adminOverride),
	)
}

func emitBatchSendEvent(channelId types.ChannelId, packetHash, batchHash types.H256) {
	chain.Emit(
		BatchSendEvent,
		"channel_id", channelId.String(),
		"packet_hash", packetHash.String(),
		"batch_hash", batchHash.String(),
	)
}

func emitBatchAcksEvent(channelId types.ChannelId, packetHash, batchHash types.H256) {
	chain.Emit(
		BatchAcksEvent,
		"channel_id", channelId.String(),
		"packet_hash", packetHash.String(),
		"batch_hash", batchHash.String(),
	)
}

func packetEventBaseAttrs(packet types.Packet) []string {
	packetData := hexAttr(packet.Data)
	attrs := []string{
		"packet_hash", commitPacketHash(packet).String(),
		"packet_data_size", strconv.Itoa(len(packetData)),
	}
	return append(attrs, eventAttrColumns("packet_data", packetData)...)
}

func eventAttrColumns(key string, value string) []string {
	if len(value) == 0 {
		return []string{key + "[0]", ""}
	}

	parts := (len(value) + maxEventAttrValueLen - 1) / maxEventAttrValueLen
	attrs := make([]string, 0, parts*2)
	for index := 0; index < parts; index++ {
		start := index * maxEventAttrValueLen
		end := start + maxEventAttrValueLen
		if end > len(value) {
			end = len(value)
		}
		attrs = append(attrs, key+"["+strconv.Itoa(index)+"]", value[start:end])
	}

	return attrs
}

func emitPacketSendEvent(packet types.Packet, sourceChannel types.Channel, sourceConnection types.Connection) {
	attrs := packetEventBaseAttrs(packet)
	attrs = append(
		attrs,
		"source_channel_id", packet.SourceChannelId.String(),
		"source_channel_version", sourceChannel.Version,
		"source_connection_id", sourceChannel.ConnectionId.String(),
		"source_connection_client_id", sourceConnection.ClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_connection_id", sourceConnection.CounterpartyConnectionId.String(),
		"destination_connection_client_id", sourceConnection.CounterpartyClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
	)
	chain.Emit(PacketSendEvent, attrs...)
}

func emitPacketRecvEvent(eventType string, packet types.Packet, destinationChannel types.Channel, connection types.Connection, msgAttrName string, msg []byte) {
	attrs := packetEventBaseAttrs(packet)
	attrs = append(
		attrs,
		"source_channel_id", packet.SourceChannelId.String(),
		"source_connection_id", connection.CounterpartyConnectionId.String(),
		"source_connection_client_id", connection.CounterpartyClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_channel_version", destinationChannel.Version,
		"destination_connection_id", destinationChannel.ConnectionId.String(),
		"destination_connection_client_id", connection.ClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
		msgAttrName, hexAttr(msg),
	)
	chain.Emit(eventType, attrs...)
}

func emitWriteAckEvent(packet types.Packet, destinationChannel types.Channel, connection types.Connection, acknowledgement []byte) {
	attrs := packetEventBaseAttrs(packet)
	attrs = append(
		attrs,
		"source_channel_id", packet.SourceChannelId.String(),
		"source_connection_id", connection.CounterpartyConnectionId.String(),
		"source_connection_client_id", connection.CounterpartyClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_channel_version", destinationChannel.Version,
		"destination_connection_id", destinationChannel.ConnectionId.String(),
		"destination_connection_client_id", connection.ClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
		"acknowledgement", hexAttr(acknowledgement),
	)
	chain.Emit(WriteAckEvent, attrs...)
}

func emitPacketAckEvent(packet types.Packet, sourceChannel types.Channel, connection types.Connection, acknowledgement []byte) {
	attrs := packetEventBaseAttrs(packet)
	attrs = append(
		attrs,
		"source_channel_id", packet.SourceChannelId.String(),
		"source_channel_version", sourceChannel.Version,
		"source_connection_id", sourceChannel.ConnectionId.String(),
		"source_connection_client_id", connection.ClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_connection_id", connection.CounterpartyConnectionId.String(),
		"destination_connection_client_id", connection.CounterpartyClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
		"acknowledgement", hexAttr(acknowledgement),
	)
	chain.Emit(PacketAckEvent, attrs...)
}

func emitPacketTimeoutEvent(packet types.Packet, sourceChannel types.Channel, connection types.Connection) {
	attrs := packetEventBaseAttrs(packet)
	attrs = append(
		attrs,
		"source_channel_id", packet.SourceChannelId.String(),
		"source_channel_version", sourceChannel.Version,
		"source_connection_id", sourceChannel.ConnectionId.String(),
		"source_connection_client_id", connection.ClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_connection_id", connection.CounterpartyConnectionId.String(),
		"destination_connection_client_id", connection.CounterpartyClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
	)
	chain.Emit(PacketTimeoutEvent, attrs...)
}

func emitCommitMembershipProofEvent(msg types.MsgCommitMembershipProof) {
	chain.Emit(
		CommitMembershipProofEvent,
		"client_id", msg.ClientId.String(),
		"proof_height", strconv.FormatUint(msg.ProofHeight, 10),
		"path", hexAttr(msg.Path),
		"value", hexAttr(msg.Value),
	)
}

func emitCommitNonMembershipProofEvent(msg types.MsgCommitNonMembershipProof) {
	chain.Emit(
		CommitNonMembershipEvent,
		"client_id", msg.ClientId.String(),
		"proof_height", strconv.FormatUint(msg.ProofHeight, 10),
		"path", hexAttr(msg.Path),
	)
}
