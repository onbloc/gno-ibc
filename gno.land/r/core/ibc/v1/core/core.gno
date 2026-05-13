package core

import (
	"chain"
	"chain/params"
	"chain/runtime"
	"crypto/keccak256"
	"encoding/hex"
)

var st State

func init() {
	st = newState()
}

// ILightClient defines the interface that light client adapters must implement.
// Methods that modify adapter state must declare _ realm as the first parameter
// (Gno crossing function requirement for cross-realm state writes).
type ILightClient interface {
	CreateClient(_ realm, clientId ClientId, clientStateBytes, consensusStateBytes []byte) string
	UpdateClient(_ realm, clientId ClientId, clientMessage []byte) ConsensusStateUpdate
	VerifyMembership(clientId ClientId, height Height, proof []byte, key []byte, value []byte)
	VerifyNonMembership(clientId ClientId, height Height, proof []byte, key []byte)
	GetTimestamp(clientId ClientId, height Height) Timestamp
	GetLatestHeight(clientId ClientId) Height
	GetStatus(clientId ClientId) Status
}

// IApp defines the interface for IBC application callbacks. Byte parameters
// use plain []byte (not the typed Bytes wrapper) so foreign-realm apps can
// implement the interface without the cross-realm typed-slice pitfall.
type IApp interface {
	OnChannelOpenInit(connectionId ConnectionId, channelId ChannelId, version string, relayer address)
	OnChannelOpenTry(connectionId ConnectionId, channelId ChannelId, version string, counterpartyVersion string, relayer address)
	OnChannelOpenAck(channelId ChannelId, counterpartyChannelId ChannelId, counterpartyVersion string, relayer address)
	OnChannelOpenConfirm(channelId ChannelId, relayer address)
	OnChannelCloseInit(channelId ChannelId, relayer address)
	OnChannelCloseConfirm(channelId ChannelId, relayer address)
	OnRecvPacket(packet Packet, relayer address, relayerMsg []byte) RecvPacketResult
	OnIntentRecvPacket(packet Packet, marketMaker address, marketMakerMsg []byte)
	OnAcknowledgementPacket(packet Packet, acknowledgement []byte, relayer address)
	OnTimeoutPacket(packet Packet, relayer address)
}

const (
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
	PacketRecvEvent            = "PacketRecv"
	IntentPacketRecvEvent      = "IntentPacketRecv"
	WriteAckEvent              = "WriteAck"
	PacketAckEvent             = "PacketAck"
	PacketTimeoutEvent         = "PacketTimeout"
)

func keccak(bz []byte) H256 {
	sum := keccak256.Sum256(bz)
	var out H256
	for i := range out {
		out[i] = sum[i]
	}
	return out
}

func commit(key H256, value H256) {
	params.SetBytes(hex.EncodeToString(key[:]), value[:])
}

// h256Bytes copies an H256 value into a fresh []byte. Required when passing
// COMMITMENT_MAGIC (a package-level array) to a foreign-realm light client:
// ics23's bytes.Equal would otherwise panic with "illegal conversion of
// readonly or externally stored value" on the underlying slice.
func h256Bytes(h H256) []byte {
	out := make([]byte, len(h))
	copy(out, h[:])
	return out
}

// safeString materializes a fresh string from a (possibly foreign-realm)
// []byte. A direct string(b) conversion on a cross-realm slice trips the
// same readonly/external-conversion guard that bytes.Equal hits, so event
// emission paths funnel through this helper.
func safeString(b []byte) string {
	out := make([]byte, len(b))
	copy(out, b)
	return string(out)
}

func emitChannelEvent(eventType string, portId Bytes, channelId ChannelId, channel Channel, connection Connection) {
	chain.Emit(eventType,
		"port_id", string(portId),
		"channel_id", channelId.String(),
		"counterparty_port_id", string(channel.CounterpartyPortId),
		"counterparty_channel_id", channel.CounterpartyChannelId.String(),
		"connection_id", channel.ConnectionId.String(),
		"connection_client_id", connection.ClientId.String(),
		"connection_counterparty_client_id", connection.CounterpartyClientId.String(),
		"connection_counterparty_connection_id", connection.CounterpartyConnectionId.String(),
		"version", channel.Version,
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

func emitPacketSendEvent(packet Packet, sourceChannel Channel, sourceConnection Connection) {
	chain.Emit(PacketSendEvent,
		"packet_hash", CommitPacket(packet).String(),
		"packet_data", string(packet.Data),
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
		"packet_data", safeString(packet.Data),
		"source_channel_id", packet.SourceChannelId.String(),
		"source_connection_id", connection.CounterpartyConnectionId.String(),
		"source_connection_client_id", connection.CounterpartyClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_channel_version", destinationChannel.Version,
		"destination_connection_id", destinationChannel.ConnectionId.String(),
		"destination_connection_client_id", connection.ClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
		msgAttrName, safeString(msg),
	)
}

func emitWriteAckEvent(packet Packet, destinationChannel Channel, connection Connection, acknowledgement []byte) {
	chain.Emit(WriteAckEvent,
		"packet_hash", CommitPacket(packet).String(),
		"packet_data", safeString(packet.Data),
		"source_channel_id", packet.SourceChannelId.String(),
		"source_connection_id", connection.CounterpartyConnectionId.String(),
		"source_connection_client_id", connection.CounterpartyClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_channel_version", destinationChannel.Version,
		"destination_connection_id", destinationChannel.ConnectionId.String(),
		"destination_connection_client_id", connection.ClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
		"acknowledgement", safeString(acknowledgement),
	)
}

func emitPacketAckEvent(packet Packet, sourceChannel Channel, connection Connection, acknowledgement []byte) {
	chain.Emit(PacketAckEvent,
		"packet_hash", CommitPacket(packet).String(),
		"packet_data", safeString(packet.Data),
		"source_channel_id", packet.SourceChannelId.String(),
		"source_channel_version", sourceChannel.Version,
		"source_connection_id", sourceChannel.ConnectionId.String(),
		"source_connection_client_id", connection.ClientId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"destination_connection_id", connection.CounterpartyConnectionId.String(),
		"destination_connection_client_id", connection.CounterpartyClientId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
		"acknowledgement", safeString(acknowledgement),
	)
}

func emitPacketTimeoutEvent(packet Packet, sourceChannel Channel, connection Connection) {
	chain.Emit(PacketTimeoutEvent,
		"packet_hash", CommitPacket(packet).String(),
		"packet_data", safeString(packet.Data),
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

func CreateClient(_ realm, msg MsgCreateClient) ClientId {
	impl, ok := st.clientRegistry[msg.ClientType]
	if !ok {
		panic(ErrClientTypeNotFound)
	}

	clientId := st.generateClientId()
	impl.CreateClient(cross, clientId, msg.ClientStateBytes, msg.ConsensusStateBytes)
	st.clientTypes[clientId] = msg.ClientType
	st.saveClientState(clientId, msg.ClientStateBytes)

	chain.Emit(CreateClientEvent,
		"client_type", string(msg.ClientType),
		"client_id", clientId.String(),
	)
	return clientId
}

func UpdateClient(_ realm, msg MsgUpdateClient) Height {
	impl := st.getClient(msg.ClientId)

	update := impl.UpdateClient(cross, msg.ClientId, msg.ClientMessage)

	st.saveClientState(msg.ClientId, update.ClientStateBytes)
	st.saveConsensusState(msg.ClientId, update.Height, update.ConsensusStateBytes)

	chain.Emit(UpdateClientEvent,
		"client_type", string(st.clientTypes[msg.ClientId]),
		"client_id", msg.ClientId.String(),
		"height", update.Height.String(),
	)
	return update.Height
}

func ConnectionOpenInit(_ realm, msg MsgConnectionOpenInit) ConnectionId {
	connectionId := st.generateConnectionId()
	st.saveConnection(connectionId, Connection{
		State:                    ConnectionStateInit,
		ClientId:                 msg.ClientId,
		CounterpartyClientId:     msg.CounterpartyClientId,
		CounterpartyConnectionId: 0,
	})
	chain.Emit(ConnectionOpenInitEvent,
		"connection_id", connectionId.String(),
		"client_id", msg.ClientId.String(),
		"counterparty_client_id", msg.CounterpartyClientId.String(),
	)
	return connectionId
}

func ConnectionOpenTry(_ realm, msg MsgConnectionOpenTry) ConnectionId {
	connectionId := st.generateConnectionId()

	expectedConnection := Connection{
		State:                    ConnectionStateInit,
		ClientId:                 msg.CounterpartyClientId,
		CounterpartyClientId:     msg.ClientId,
		CounterpartyConnectionId: 0,
	}
	key := ConnectionPath(msg.CounterpartyConnectionId)
	value := keccak(expectedConnection.EthAbiEncode())
	st.getClient(msg.ClientId).VerifyMembership(msg.ClientId, msg.ProofHeight, msg.ProofInit, key[:], value[:])

	st.saveConnection(connectionId, Connection{
		State:                    ConnectionStateTryOpen,
		ClientId:                 msg.ClientId,
		CounterpartyClientId:     msg.CounterpartyClientId,
		CounterpartyConnectionId: msg.CounterpartyConnectionId,
	})
	chain.Emit(ConnectionOpenTryEvent,
		"connection_id", connectionId.String(),
		"client_id", msg.ClientId.String(),
		"counterparty_client_id", msg.CounterpartyClientId.String(),
		"counterparty_connection_id", msg.CounterpartyConnectionId.String(),
	)
	return connectionId
}

func ConnectionOpenAck(_ realm, msg MsgConnectionOpenAck) {
	connection := st.getConnection(msg.ConnectionId)
	if connection.State != ConnectionStateInit {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := Connection{
		State:                    ConnectionStateTryOpen,
		ClientId:                 connection.CounterpartyClientId,
		CounterpartyClientId:     connection.ClientId,
		CounterpartyConnectionId: msg.ConnectionId,
	}
	key := ConnectionPath(msg.CounterpartyConnectionId)
	value := keccak(expectedConnection.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofTry, key[:], value[:])

	connection.State = ConnectionStateOpen
	connection.CounterpartyConnectionId = msg.CounterpartyConnectionId
	st.saveConnection(msg.ConnectionId, connection)

	chain.Emit(ConnectionOpenAckEvent,
		"connection_id", msg.ConnectionId.String(),
		"client_id", connection.ClientId.String(),
		"counterparty_client_id", connection.CounterpartyClientId.String(),
		"counterparty_connection_id", msg.CounterpartyConnectionId.String(),
	)
}

func ConnectionOpenConfirm(_ realm, msg MsgConnectionOpenConfirm) {
	connection := st.getConnection(msg.ConnectionId)
	if connection.State != ConnectionStateTryOpen {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := Connection{
		State:                    ConnectionStateOpen,
		ClientId:                 connection.CounterpartyClientId,
		CounterpartyClientId:     connection.ClientId,
		CounterpartyConnectionId: msg.ConnectionId,
	}
	key := ConnectionPath(connection.CounterpartyConnectionId)
	value := keccak(expectedConnection.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofAck, key[:], value[:])

	connection.State = ConnectionStateOpen
	st.saveConnection(msg.ConnectionId, connection)

	chain.Emit(ConnectionOpenConfirmEvent,
		"connection_id", msg.ConnectionId.String(),
		"client_id", connection.ClientId.String(),
		"counterparty_client_id", connection.CounterpartyClientId.String(),
		"counterparty_connection_id", connection.CounterpartyConnectionId.String(),
	)
}

func ChannelOpenInit(_ realm, msg MsgChannelOpenInit) ChannelId {
	relayer := runtime.OriginCaller()
	portId := msg.PortId
	connection := ensureConnectionOpen(msg.ConnectionId)
	channelId := st.generateChannelId()
	st.channelOwners[channelId] = portId

	st.getAppByPortId(portId).OnChannelOpenInit(msg.ConnectionId, channelId, msg.Version, relayer)

	channel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    msg.CounterpartyPortId,
		Version:               msg.Version,
	}
	st.saveChannel(channelId, channel)
	emitChannelEvent(ChannelOpenInitEvent, portId, channelId, channel, connection)
	return channelId
}

func ChannelOpenTry(_ realm, msg MsgChannelOpenTry) ChannelId {
	relayer := runtime.OriginCaller()
	portId := msg.PortId
	if msg.Channel.State != ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(msg.Channel.ConnectionId)
	channelId := st.generateChannelId()

	expectedChannel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.Channel.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    msg.PortId,
		Version:               msg.Channel.Version,
	}
	key := ChannelPath(msg.Channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofInit, key[:], value[:])

	st.channelOwners[channelId] = portId
	st.getAppByPortId(portId).OnChannelOpenTry(msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, relayer)
	st.saveChannel(channelId, msg.Channel)

	emitChannelEvent(ChannelOpenTryEvent, portId, channelId, msg.Channel, connection)
	return channelId
}

func ChannelOpenAck(_ realm, msg MsgChannelOpenAck) {
	relayer := runtime.OriginCaller()
	channel := st.getChannel(msg.ChannelId)
	if channel.State != ChannelStateInit {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)

	expectedChannel := Channel{
		State:                 ChannelStateTryOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               msg.CounterpartyVersion,
	}
	key := ChannelPath(msg.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofTry, key[:], value[:])

	st.getAppByPortId(portId).OnChannelOpenAck(msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, relayer)

	channel.State = ChannelStateOpen
	channel.Version = msg.CounterpartyVersion
	channel.CounterpartyChannelId = msg.CounterpartyChannelId
	st.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenAckEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelOpenConfirm(_ realm, msg MsgChannelOpenConfirm) {
	relayer := runtime.OriginCaller()
	channel := st.getChannel(msg.ChannelId)
	if channel.State != ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)

	expectedChannel := Channel{
		State:                 ChannelStateOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               channel.Version,
	}
	key := ChannelPath(channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofAck, key[:], value[:])

	st.getAppByPortId(portId).OnChannelOpenConfirm(msg.ChannelId, relayer)
	channel.State = ChannelStateOpen
	st.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenConfirmEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelCloseInit(_ realm, msg MsgChannelCloseInit) {
	panic("channel close init unsupported: Union MsgChannelCloseInit has no channel id")
}

func ChannelCloseConfirm(_ realm, msg MsgChannelCloseConfirm) {
	panic("channel close confirm unsupported: Union MsgChannelCloseConfirm has no channel id")
}

func PacketSend(_ realm, sourceChannelId ChannelId, timeoutHeight Height, timeoutTimestamp Timestamp, data []byte) Packet {
	portId := st.getChannelOwner(sourceChannelId)
	if string(portId) != runtime.PreviousRealm().Address().String() {
		panic(ErrUnauthorizedPacketSender)
	}

	channel := st.getChannel(sourceChannelId)
	if channel.State != ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)

	packet := Packet{
		SourceChannelId:      sourceChannelId,
		DestinationChannelId: channel.CounterpartyChannelId,
		Data:                 data,
		TimeoutHeight:        timeoutHeight,
		TimeoutTimestamp:     timeoutTimestamp,
	}
	st.commitPacket(packet)

	emitPacketSendEvent(packet, channel, connection)
	return packet
}

func PacketRecv(_ realm, msg MsgPacketRecv) {
	relayer := runtime.OriginCaller()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	firstChannel := st.getChannel(first.DestinationChannelId)
	firstConnection := ensureConnectionOpen(firstChannel.ConnectionId)
	batchKey := BatchPacketsPath(CommitPackets(msg.Packets))
	st.getClient(firstConnection.ClientId).VerifyMembership(
		firstConnection.ClientId, msg.ProofHeight, msg.Proof, batchKey[:], h256Bytes(COMMITMENT_MAGIC),
	)

	for i, packet := range msg.Packets {
		channel := st.getChannel(packet.DestinationChannelId)
		if channel.State != ChannelStateOpen {
			panic(ErrInvalidChannelState)
		}
		if packet.DestinationChannelId != first.DestinationChannelId {
			panic(ErrBatchSameChannelOnly)
		}

		// Receipt presence is the replay-protection signal: skip silently so
		// honest relayers can re-submit batches without aborting the whole tx.
		if st.hasPacketReceipt(packet) {
			continue
		}

		st.setPacketReceipt(packet)

		var relayerMsg []byte
		if i < len(msg.RelayerMsgs) {
			relayerMsg = msg.RelayerMsgs[i]
		}
		portId := st.getChannelOwner(packet.DestinationChannelId)
		res := st.getAppByPortId(portId).OnRecvPacket(packet, relayer, relayerMsg)
		switch res.Status {
		case PacketStatusAsync:
			st.savePendingAsyncAck(packet)
		case PacketStatusSuccess, PacketStatusFailure:
			if len(res.Ack) == 0 {
				panic(ErrSyncAckEmpty)
			}
			st.commitAcknowledgement(packet, res.Ack)
			emitWriteAckEvent(packet, channel, firstConnection, res.Ack)
		default:
			panic(ErrUnknownPacketStatus)
		}

		emitPacketRecvEvent(PacketRecvEvent, packet, channel, firstConnection, "maker_msg", relayerMsg)
	}
}

func IntentPacketRecv(_ realm, msg MsgIntentPacketRecv) {
	marketMaker := runtime.OriginCaller()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]

	for i, packet := range msg.Packets {
		channel := st.getChannel(packet.DestinationChannelId)
		if channel.State != ChannelStateOpen {
			panic(ErrInvalidChannelState)
		}
		if packet.DestinationChannelId != first.DestinationChannelId {
			panic(ErrBatchSameChannelOnly)
		}
		if st.hasPacketReceipt(packet) {
			continue
		}

		st.setPacketReceipt(packet)

		var marketMakerMsg []byte
		if i < len(msg.MarketMakerMessages) {
			marketMakerMsg = msg.MarketMakerMessages[i]
		}
		portId := st.getChannelOwner(packet.DestinationChannelId)
		st.getAppByPortId(portId).OnIntentRecvPacket(packet, marketMaker, marketMakerMsg)

		connection := ensureConnectionOpen(channel.ConnectionId)
		emitPacketRecvEvent(IntentPacketRecvEvent, packet, channel, connection, "market_maker_msg", marketMakerMsg)
	}
}

func PacketAcknowledgement(_ realm, msg MsgPacketAcknowledgement) {
	relayer := runtime.OriginCaller()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	if len(msg.Packets) != len(msg.Acknowledgements) {
		panic(ErrAcknowledgementCountMismatch)
	}
	first := msg.Packets[0]
	channel := st.getChannel(first.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)
	key := BatchReceiptsPath(CommitPackets(msg.Packets))
	value := CommitAcks(msg.Acknowledgements)
	st.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId, msg.ProofHeight, msg.Proof, key[:], value[:],
	)

	for i, packet := range msg.Packets {
		if !st.hasPacketCommitment(packet) {
			continue
		}
		if packet.SourceChannelId != first.SourceChannelId {
			panic(ErrBatchSameChannelOnly)
		}

		ack := msg.Acknowledgements[i]
		portId := st.getChannelOwner(packet.SourceChannelId)
		st.getAppByPortId(portId).OnAcknowledgementPacket(packet, ack, relayer)

		st.deletePacketCommitment(packet)

		emitPacketAckEvent(packet, channel, connection, ack)
	}
}

func PacketTimeout(_ realm, msg MsgPacketTimeout) {
	relayer := runtime.OriginCaller()
	packet := msg.Packet
	if !st.hasPacketCommitment(packet) {
		return
	}

	channel := st.getChannel(packet.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	key := BatchReceiptsPath(CommitPacket(packet))
	st.getClient(connection.ClientId).VerifyNonMembership(
		connection.ClientId, msg.ProofHeight, msg.Proof, key[:],
	)

	portId := st.getChannelOwner(packet.SourceChannelId)
	st.getAppByPortId(portId).OnTimeoutPacket(packet, relayer)

	st.deletePacketCommitment(packet)

	emitPacketTimeoutEvent(packet, channel, connection)
}

// HasPacketCommitment exposes packet commitment presence for filetests and
// lifecycle diagnostics.
func HasPacketCommitment(_ realm, packet Packet) bool {
	return st.hasPacketCommitment(packet)
}

// HasPacketReceipt exposes packet receipt presence for filetests and
// lifecycle diagnostics.
func HasPacketReceipt(_ realm, packet Packet) bool {
	return st.hasPacketReceipt(packet)
}

// HasAcknowledgement exposes packet acknowledgement presence for filetests and
// lifecycle diagnostics.
func HasAcknowledgement(_ realm, packet Packet) bool {
	return st.hasAcknowledgement(packet)
}

// AcknowledgementHash exposes the committed Union-spec acknowledgement hash
// (CommitAcks of the single ack) for filetests and lifecycle diagnostics.
func AcknowledgementHash(_ realm, packet Packet) H256 {
	return st.acknowledgementHash(packet)
}

func BatchSend(_ realm, msg MsgBatchSend) H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	batchHash := CommitPackets(msg.Packets)
	commit(BatchPacketsPath(batchHash), COMMITMENT_MAGIC)
	// In-memory per-packet membership keeps HasPacketCommitment and the
	// PacketAcknowledgement / PacketTimeout cleanup paths working for
	// single-packet sends; multi-packet batches still commit at the batch
	// path on chain.
	for _, packet := range msg.Packets {
		st.packetCommitments[PacketCommitmentPath(packet)] = true
	}
	first := msg.Packets[0]
	channel := st.getChannel(first.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)
	emitBatchSendEvent(batchHash, first, channel, connection)
	return batchHash
}

func BatchAcks(_ realm, msg MsgBatchAcks) H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	if len(msg.Packets) != len(msg.Acks) {
		panic(ErrAcknowledgementCountMismatch)
	}
	batchHash := CommitPackets(msg.Packets)
	commit(BatchReceiptsPath(batchHash), CommitAcks(msg.Acks))
	return batchHash
}

func CommitMembershipProof(_ realm, msg MsgCommitMembershipProof) {
	st.getClient(msg.ClientId).VerifyMembership(msg.ClientId, msg.ProofHeight, msg.Proof, msg.Path, msg.Value)
	key := MembershipProofPath(msg.ClientId, msg.ProofHeight, msg.Path)
	params.SetBytes(hex.EncodeToString(key[:]), msg.Value)
}

func CommitNonMembershipProof(_ realm, msg MsgCommitNonMembershipProof) {
	st.getClient(msg.ClientId).VerifyNonMembership(msg.ClientId, msg.ProofHeight, msg.Proof, msg.Path)
	commit(NonMembershipProofPath(msg.ClientId, msg.ProofHeight, msg.Path), COMMITMENT_MAGIC)
}

// RegisterClient registers a light client implementation under the given
// client type. Apps and chain operators call this from a loader realm at init.
func RegisterClient(_ realm, clientType ClientType, client ILightClient) {
	st.registerClient(clientType, client)
}

// RegisterApp registers an IBC application implementation at the given port
// id. Port ids are arbitrary bytes (per Union spec) — typically the realm
// address string bytes. The parameter type is plain []byte so foreign-realm
// loaders can pass values without hitting the typed-slice cross-realm pitfall;
// conversion to the typed Bytes wrapper happens inside this realm.
func RegisterApp(_ realm, portId []byte, app IApp) {
	key := string(portId)
	if _, ok := st.ports[key]; ok {
		panic(ErrPortAlreadyRegistered)
	}
	st.ports[key] = app
}

// HasApp reports whether an app is registered at portId. Loaders can branch on
// this for idempotent registration (e.g. running tests that reuse the same
// proxy realm address). string(portId) builds the lookup key without invoking
// the foreign-typed-slice conversion that tripped on Bytes(portId) earlier.
func HasApp(portId []byte) bool {
	_, ok := st.ports[string(portId)]
	return ok
}

// HasClient reports whether a light client is registered for clientType.
func HasClient(clientType ClientType) bool {
	_, ok := st.clientRegistry[clientType]
	return ok
}

// WriteAcknowledgement drains a pending async acknowledgement saved when an
// app's OnRecvPacket returned PacketStatusAsync. It commits the acknowledgement
// against the packet's destination channel, emits WriteAck, and clears the
// pending entry.
func WriteAcknowledgement(_ realm, msg MsgWriteAcknowledgement) {
	hash := CommitPacket(msg.Packet)
	pending, ok := st.pendingAsyncAcks[hash]
	if !ok {
		panic(ErrNoPendingAsyncAck)
	}
	portId := st.getChannelOwner(pending.Packet.DestinationChannelId)
	if string(portId) != runtime.PreviousRealm().Address().String() {
		panic(ErrUnauthorizedAckWriter)
	}
	if len(msg.Acknowledgement) == 0 {
		panic(ErrAcknowledgementEmpty)
	}
	channel := st.getChannel(pending.Packet.DestinationChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	st.commitAcknowledgement(pending.Packet, msg.Acknowledgement)
	delete(st.pendingAsyncAcks, hash)

	emitWriteAckEvent(pending.Packet, channel, connection, msg.Acknowledgement)
}

// GetChannel returns the stored channel record for channelId. Apps need this
// to look up the counterparty channel id when constructing packets to send via
// BatchSend (the core no longer auto-derives it from a sender-side helper).
func GetChannel(channelId ChannelId) Channel {
	return st.getChannel(channelId)
}

func CommitPacketTimeout(_ realm, msg MsgCommitPacketTimeout) {
	key := BatchTimeoutPath(msg.Packet)
	channel := st.getChannel(msg.Packet.SourceChannelId)
	connection := st.getConnection(channel.ConnectionId)
	st.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId,
		msg.ProofHeight,
		msg.Proof,
		key[:],
		h256Bytes(COMMITMENT_MAGIC),
	)
	commit(key, COMMITMENT_MAGIC)
}

func Render(_ string) string {
	s := "next client id: " + st.nextClientId.String()
	s += "\nregistered clients: ["
	for key := range st.clientRegistry {
		s += " " + string(key)
	}
	s += " ]"
	return s
}

func ensureConnectionOpen(connectionId ConnectionId) Connection {
	connection := st.getConnection(connectionId)
	if connection.State != ConnectionStateOpen {
		panic(ErrInvalidConnectionState)
	}
	return connection
}
