package core

import (
	"chain"
	"strconv"
)

const (
	AdminChangedEvent          = "AdminChanged"
	ClientRegisteredEvent      = "ClientRegistered"
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

func channelEventAttrs(eventType string, portId Bytes, channelId ChannelId, channel Channel, connection Connection) []string {
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

func emitChannelEvent(eventType string, portId Bytes, channelId ChannelId, channel Channel, connection Connection) {
	chain.Emit(eventType, channelEventAttrs(eventType, portId, channelId, channel, connection)...)
}

func emitAdminChangedEvent(oldAdmin address, newAdmin address) {
	chain.Emit(AdminChangedEvent,
		"old_admin", oldAdmin.String(),
		"new_admin", newAdmin.String(),
	)
}

func emitClientRegisteredEvent(clientType ClientType, registrarPkgPath string, adminOverride bool) {
	chain.Emit(ClientRegisteredEvent,
		"client_type", clientType.String(),
		"registrar_pkg_path", registrarPkgPath,
		"admin_override", strconv.FormatBool(adminOverride),
	)
}

func emitAppRegisteredEvent(portId []byte, registrarPkgPath string, adminOverride bool) {
	chain.Emit(AppRegisteredEvent,
		"port_id", string(portId),
		"registrar_pkg_path", registrarPkgPath,
		"admin_override", strconv.FormatBool(adminOverride),
	)
}

func emitBatchSendEvent(batchHash H256, packet Packet, sourceChannel Channel, sourceConnection Connection) {
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

func emitBatchAcksEvent(batchHash H256, ackHash H256, packet Packet, destinationChannel Channel, destinationConnection Connection) {
	chain.Emit(BatchAcksEvent,
		"batch_hash", batchHash.String(),
		"ack_hash", ackHash.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_channel_version", destinationChannel.Version,
		"destination_connection_id", destinationChannel.ConnectionId.String(),
		"destination_connection_client_id", destinationConnection.ClientId.String(),
	)
}

func emitPacketSendEvent(packet Packet, sourceChannel Channel, sourceConnection Connection) {
	chain.Emit(PacketSendEvent,
		"packet_hash", CommitPacket(packet).String(),
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

func emitPacketRecvEvent(eventType string, packet Packet, destinationChannel Channel, connection Connection, msgAttrName string, msg []byte) {
	chain.Emit(eventType,
		"packet_hash", CommitPacket(packet).String(),
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

func emitWriteAckEvent(packet Packet, destinationChannel Channel, connection Connection, acknowledgement []byte) {
	chain.Emit(WriteAckEvent,
		"packet_hash", CommitPacket(packet).String(),
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

func emitPacketAckEvent(packet Packet, sourceChannel Channel, connection Connection, acknowledgement []byte) {
	chain.Emit(PacketAckEvent,
		"packet_hash", CommitPacket(packet).String(),
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

func emitPacketTimeoutEvent(packet Packet, sourceChannel Channel, connection Connection) {
	chain.Emit(PacketTimeoutEvent,
		"packet_hash", CommitPacket(packet).String(),
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
