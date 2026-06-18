package core

import (
	"chain"
	"strconv"

	"gno.land/p/onbloc/ibc/union/types"
)

const (
	AdminChangedEvent          = "AdminChanged"
	AppRegisteredEvent         = "AppRegistered"
	CreateClientEvent          = "CreateClient"
	UpdateClientEvent          = "UpdateClient"
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
)

func channelEventAttrs(eventType string, portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) []string {
	attrs := []string{
		"port_id", string(portId),
		"channel_id", channelId.String(),
		"counterparty_port_id", channel.CounterpartyPortId.String(),
	}
	// ChannelOpenInit has not learned the counterparty channel id yet.
	// state.gno starts real channel ids at 1, so the zero value is only an unset sentinel.
	if eventType != ChannelOpenInitEvent {
		attrs = append(attrs,
			"counterparty_channel_id", channel.CounterpartyChannelId.String(),
		)
	}
	attrs = append(attrs,
		"connection_id", channel.ConnectionId.String(),
		"connection_client_id", connection.ClientId.String(),
		"connection_counterparty_client_id", connection.CounterpartyClientId.String(),
		"connection_counterparty_connection_id", connection.CounterpartyConnectionId.String(),
		"version", channel.Version,
	)
	return attrs
}

func emitChannelEvent(eventType string, portId types.Bytes, channelId types.ChannelId, channel types.Channel, connection types.Connection) {
	chain.Emit(eventType, channelEventAttrs(eventType, portId, channelId, channel, connection)...)
}

func emitConnectionOpenInitEvent(connectionId types.ConnectionId, clientId types.ClientId, counterpartyClientId types.ClientId) {
	chain.Emit(ConnectionOpenInitEvent,
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

func emitAdminChangedEvent(oldAdmin address, newAdmin address) {
	chain.Emit(AdminChangedEvent,
		"old_admin", oldAdmin.String(),
		"new_admin", newAdmin.String(),
	)
}

func emitAppRegisteredEvent(portId []byte, registrarPkgPath string, adminOverride bool) {
	chain.Emit(AppRegisteredEvent,
		"port_id", string(portId),
		"registrar_pkg_path", registrarPkgPath,
		"admin_override", strconv.FormatBool(adminOverride),
	)
}

func emitBatchSendEvent(batchHash types.H256, packet types.Packet, sourceChannel types.Channel, sourceConnection types.Connection) {
	chain.Emit(BatchSendEvent,
		"batch_hash", batchHash.String(),
		"source_channel_id", packet.SourceChannelId.String(),
		"source_channel_version", sourceChannel.Version,
		"source_connection_id", sourceChannel.ConnectionId.String(),
		"source_connection_client_id", sourceConnection.ClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_connection_id", sourceConnection.CounterpartyConnectionId.String(),
		"destination_connection_client_id", sourceConnection.CounterpartyClientId.String(),
	)
}

func emitBatchAcksEvent(batchHash types.H256, ackHash types.H256, packet types.Packet, destinationChannel types.Channel, destinationConnection types.Connection) {
	chain.Emit(BatchAcksEvent,
		"batch_hash", batchHash.String(),
		"ack_hash", ackHash.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_channel_version", destinationChannel.Version,
		"destination_connection_id", destinationChannel.ConnectionId.String(),
		"destination_connection_client_id", destinationConnection.ClientId.String(),
	)
}

func emitPacketSendEvent(packet types.Packet, sourceChannel types.Channel, sourceConnection types.Connection) {
	chain.Emit(PacketSendEvent,
		"packet_hash", commitPacketHash(packet).String(),
		"packet_data", hexAttr(packet.Data),
		"source_channel_id", packet.SourceChannelId.String(),
		"source_channel_version", sourceChannel.Version,
		"source_connection_id", sourceChannel.ConnectionId.String(),
		"source_connection_client_id", sourceConnection.ClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_connection_id", sourceConnection.CounterpartyConnectionId.String(),
		"destination_connection_client_id", sourceConnection.CounterpartyClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
	)
}

func emitPacketRecvEvent(eventType string, packet types.Packet, destinationChannel types.Channel, connection types.Connection, msgAttrName string, msg []byte) {
	chain.Emit(eventType,
		"packet_hash", commitPacketHash(packet).String(),
		"packet_data", hexAttr(packet.Data),
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
}

func emitWriteAckEvent(packet types.Packet, destinationChannel types.Channel, connection types.Connection, acknowledgement []byte) {
	chain.Emit(WriteAckEvent,
		"packet_hash", commitPacketHash(packet).String(),
		"packet_data", hexAttr(packet.Data),
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
}

func emitPacketAckEvent(packet types.Packet, sourceChannel types.Channel, connection types.Connection, acknowledgement []byte) {
	chain.Emit(PacketAckEvent,
		"packet_hash", commitPacketHash(packet).String(),
		"packet_data", hexAttr(packet.Data),
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
}

func emitPacketTimeoutEvent(packet types.Packet, sourceChannel types.Channel, connection types.Connection) {
	chain.Emit(PacketTimeoutEvent,
		"packet_hash", commitPacketHash(packet).String(),
		"packet_data", hexAttr(packet.Data),
		"source_channel_id", packet.SourceChannelId.String(),
		"source_channel_version", sourceChannel.Version,
		"source_connection_id", sourceChannel.ConnectionId.String(),
		"source_connection_client_id", connection.ClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_connection_id", connection.CounterpartyConnectionId.String(),
		"destination_connection_client_id", connection.CounterpartyClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
	)
}
