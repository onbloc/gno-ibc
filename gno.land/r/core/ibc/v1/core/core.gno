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

// IApp defines the interface for IBC application callbacks.
type IApp interface {
	OnChannelOpenInit(connectionId ConnectionId, channelId ChannelId, version string, relayer address)
	OnChannelOpenTry(connectionId ConnectionId, channelId ChannelId, version string, counterpartyVersion string, relayer address)
	OnChannelOpenAck(channelId ChannelId, counterpartyChannelId ChannelId, counterpartyVersion string, relayer address)
	OnChannelOpenConfirm(channelId ChannelId, relayer address)
	OnChannelCloseInit(channelId ChannelId, relayer address)
	OnChannelCloseConfirm(channelId ChannelId, relayer address)
	OnRecvPacket(packet Packet, relayer address, relayerMsg Bytes) RecvPacketResult
	OnIntentRecvPacket(packet Packet, marketMaker address, marketMakerMsg Bytes)
	OnAcknowledgementPacket(packet Packet, acknowledgement Bytes, relayer address)
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
	PacketRecvEvent            = "PacketRecv"
	IntentPacketRecvEvent      = "IntentPacketRecv"
	WriteAckEvent              = "WriteAck"
	PacketAckEvent             = "PacketAck"
	PacketTimeoutEvent         = "PacketTimeout"
)

func keccak(bz []byte) H256 {
	return keccak256.Sum256(bz)
}

func commit(key H256, value H256) {
	params.SetBytes(hex.EncodeToString(key[:]), value[:])
}

func CreateClient(_ realm, msg MsgCreateClient) ClientId {
	relayer := runtime.OriginCaller()
	impl, ok := st.clientRegistry[msg.ClientType]
	if !ok {
		panic(ErrClientTypeNotFound)
	}

	clientId := st.generateClientId()
	counterpartyChainId := impl.CreateClient(cross, clientId, msg.ClientStateBytes, msg.ConsensusStateBytes)
	st.clientTypes[clientId] = msg.ClientType
	st.saveClientState(clientId, msg.ClientStateBytes)

	chain.Emit(CreateClientEvent,
		"client_type", string(msg.ClientType),
		"client_id", clientId.String(),
		"counterparty_chain_id", counterpartyChainId,
		"relayer", string(relayer),
	)
	return clientId
}

func UpdateClient(_ realm, msg MsgUpdateClient) Height {
	relayer := runtime.OriginCaller()
	impl := st.getClient(msg.ClientId)

	update := impl.UpdateClient(cross, msg.ClientId, msg.ClientMessage)

	st.saveClientState(msg.ClientId, update.ClientStateBytes)
	st.saveConsensusState(msg.ClientId, update.Height, update.ConsensusStateBytes)

	chain.Emit(UpdateClientEvent,
		"client_id", msg.ClientId.String(),
		"height", update.Height.String(),
		"relayer", string(relayer),
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
	)
}

func ChannelOpenInit(_ realm, msg MsgChannelOpenInit) ChannelId {
	relayer := runtime.OriginCaller()
	portId := msg.PortId
	ensureConnectionOpen(msg.ConnectionId)
	channelId := st.generateChannelId()
	st.channelOwners[channelId] = portId

	st.getAppByPortId(portId).OnChannelOpenInit(msg.ConnectionId, channelId, msg.Version, relayer)

	st.saveChannel(channelId, Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    msg.CounterpartyPortId,
		Version:               msg.Version,
	})
	chain.Emit(ChannelOpenInitEvent,
		"channel_id", channelId.String(),
		"connection_id", msg.ConnectionId.String(),
	)
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

	chain.Emit(ChannelOpenTryEvent,
		"channel_id", channelId.String(),
		"connection_id", msg.Channel.ConnectionId.String(),
	)
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

	chain.Emit(ChannelOpenAckEvent,
		"channel_id", msg.ChannelId.String(),
		"counterparty_channel_id", msg.CounterpartyChannelId.String(),
	)
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

	chain.Emit(ChannelOpenConfirmEvent,
		"channel_id", msg.ChannelId.String(),
	)
}

func ChannelCloseInit(_ realm, msg MsgChannelCloseInit) {
	panic("channel close init unsupported: Union MsgChannelCloseInit has no channel id")
}

func ChannelCloseConfirm(_ realm, msg MsgChannelCloseConfirm) {
	panic("channel close confirm unsupported: Union MsgChannelCloseConfirm has no channel id")
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
		firstConnection.ClientId, msg.ProofHeight, msg.Proof, batchKey[:], COMMITMENT_MAGIC[:],
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

		var relayerMsg Bytes
		if i < len(msg.RelayerMsgs) {
			relayerMsg = msg.RelayerMsgs[i]
		}
		portId := st.getChannelOwner(packet.DestinationChannelId)
		res := st.getAppByPortId(portId).OnRecvPacket(packet, relayer, relayerMsg)
		switch res.Status {
		case PacketStatusAsync:
			st.savePendingAsyncAck(packet, portId)
		case PacketStatusSuccess, PacketStatusFailure:
			if len(res.Ack) == 0 {
				panic(ErrSyncAckEmpty)
			}
			st.commitAcknowledgement(packet, res.Ack)
			ackHash := keccak(res.Ack)
			chain.Emit(WriteAckEvent,
				"source_channel_id", packet.SourceChannelId.String(),
				"destination_channel_id", packet.DestinationChannelId.String(),
				"packet_hash", CommitPacket(packet).String(),
				"ack_hash_hex", hex.EncodeToString(ackHash[:]),
				"deferred", "false",
			)
		default:
			panic(ErrUnknownPacketStatus)
		}

		chain.Emit(PacketRecvEvent,
			"source_channel_id", packet.SourceChannelId.String(),
			"destination_channel_id", packet.DestinationChannelId.String(),
			"packet_hash", CommitPacket(packet).String(),
		)
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

		var marketMakerMsg Bytes
		if i < len(msg.MarketMakerMessages) {
			marketMakerMsg = msg.MarketMakerMessages[i]
		}
		portId := st.getChannelOwner(packet.DestinationChannelId)
		st.getAppByPortId(portId).OnIntentRecvPacket(packet, marketMaker, marketMakerMsg)

		chain.Emit(IntentPacketRecvEvent,
			"source_channel_id", packet.SourceChannelId.String(),
			"destination_channel_id", packet.DestinationChannelId.String(),
			"packet_hash", CommitPacket(packet).String(),
			"market_maker", string(marketMaker),
		)
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

		chain.Emit(PacketAckEvent,
			"source_channel_id", packet.SourceChannelId.String(),
			"destination_channel_id", packet.DestinationChannelId.String(),
			"relayer", string(relayer),
		)
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

	chain.Emit(PacketTimeoutEvent,
		"source_channel_id", packet.SourceChannelId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"relayer", string(relayer),
	)
}

func BatchSend(_ realm, msg MsgBatchSend) H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	batchHash := CommitPackets(msg.Packets)
	commit(BatchPacketsPath(batchHash), COMMITMENT_MAGIC)
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

func CommitPacketTimeout(_ realm, msg MsgCommitPacketTimeout) {
	key := BatchTimeoutPath(msg.Packet)
	channel := st.getChannel(msg.Packet.SourceChannelId)
	connection := st.getConnection(channel.ConnectionId)
	st.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId,
		msg.ProofHeight,
		msg.Proof,
		key[:],
		COMMITMENT_MAGIC[:],
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
