package core

import (
	"chain"
	"chain/params"
	"crypto/keccak256"
	"encoding/hex"
)

var st State

func init() {
	st = State{
		nextClientId:     ClientId(1),
		nextConnectionId: ConnectionId(1),
		nextChannelId:    ChannelId(1),
		clientRegistry:   make(map[ClientType]ILightClient),
		clientTypes:      make(map[ClientId]ClientType),
		connections:      make(map[ConnectionId]Connection),
		channels:         make(map[ChannelId]Channel),
		ports:            make(map[address]IApp),
		channelOwners:    make(map[ChannelId]address),
	}
}

// ILightClient defines the interface that light client adapters must implement.
// Methods that modify adapter state must declare _ realm as the first parameter
// (Gno crossing function requirement for cross-realm state writes).
type ILightClient interface {
	CreateClient(_ realm, clientId ClientId, clientStateBytes, consensusStateBytes []byte) string
	UpdateClient(_ realm, clientId ClientId, clientMessage []byte) ConsensusStateUpdate
	Misbehaviour(_ realm, clientId ClientId, clientMessage []byte) []byte
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
	OnRecvPacket(packet Packet, relayer address, relayerMsg Bytes)
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
	MisbehaviourEvent          = "Misbehaviour"
	ChannelOpenInitEvent       = "ChannelOpenInit"
	ChannelOpenTryEvent        = "ChannelOpenTry"
	ChannelOpenAckEvent        = "ChannelOpenAck"
	ChannelOpenConfirmEvent    = "ChannelOpenConfirm"
	ChannelCloseInitEvent      = "ChannelCloseInit"
	ChannelCloseConfirmEvent   = "ChannelCloseConfirm"
	PacketSendEvent            = "PacketSend"
	PacketRecvEvent            = "PacketRecv"
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

func getCommit(key H256) H256 {
	// params doesn't expose getters; used only for existence checks in tests
	// In production Union queries ABCI directly
	var zero H256
	return zero
}

func RegisterClient(_ realm, clientType ClientType, client ILightClient) {
	st.registerClient(clientType, client)
}

func RegisterApp(_ realm, portId address, app IApp) {
	if _, ok := st.ports[portId]; ok {
		panic("port already registered")
	}
	st.ports[portId] = app
}

func CreateClient(_ realm, msg MsgCreateClient) ClientId {
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
		"relayer", string(msg.Relayer),
	)
	return clientId
}

func UpdateClient(_ realm, msg MsgUpdateClient) Height {
	impl := st.getClient(msg.ClientId)

	update := impl.UpdateClient(cross, msg.ClientId, msg.ClientMessage)

	st.saveClientState(msg.ClientId, update.ClientStateBytes)
	st.saveConsensusState(msg.ClientId, update.Height, update.ConsensusStateBytes)

	chain.Emit(UpdateClientEvent,
		"client_id", msg.ClientId.String(),
		"height", update.Height.String(),
		"relayer", string(msg.Relayer),
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
	ensureConnectionOpen(msg.ConnectionId)
	channelId := st.generateChannelId()
	st.channelOwners[channelId] = msg.PortId

	st.getAppByPortId(msg.PortId).OnChannelOpenInit(msg.ConnectionId, channelId, msg.Version, msg.Relayer)

	st.saveChannel(channelId, Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    Bytes(msg.CounterpartyPortId[:]),
		Version:               msg.Version,
	})
	chain.Emit(ChannelOpenInitEvent,
		"channel_id", channelId.String(),
		"connection_id", msg.ConnectionId.String(),
	)
	return channelId
}

func ChannelOpenTry(_ realm, msg MsgChannelOpenTry) ChannelId {
	if msg.Channel.State != ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(msg.Channel.ConnectionId)
	channelId := st.generateChannelId()

	expectedChannel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.Channel.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    Bytes(msg.PortId[:]),
		Version:               msg.Channel.Version,
	}
	key := ChannelPath(msg.Channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofInit, key[:], value[:])

	st.channelOwners[channelId] = msg.PortId
	st.getAppByPortId(msg.PortId).OnChannelOpenTry(msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, msg.Relayer)
	st.saveChannel(channelId, msg.Channel)

	chain.Emit(ChannelOpenTryEvent,
		"channel_id", channelId.String(),
		"connection_id", msg.Channel.ConnectionId.String(),
	)
	return channelId
}

func ChannelOpenAck(_ realm, msg MsgChannelOpenAck) {
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
		CounterpartyPortId:    Bytes(portId[:]),
		Version:               msg.CounterpartyVersion,
	}
	key := ChannelPath(msg.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofTry, key[:], value[:])

	st.getAppByPortId(portId).OnChannelOpenAck(msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, msg.Relayer)

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
		CounterpartyPortId:    Bytes(portId[:]),
		Version:               channel.Version,
	}
	key := ChannelPath(channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofAck, key[:], value[:])

	st.getAppByPortId(portId).OnChannelOpenConfirm(msg.ChannelId, msg.Relayer)
	channel.State = ChannelStateOpen
	st.saveChannel(msg.ChannelId, channel)

	chain.Emit(ChannelOpenConfirmEvent,
		"channel_id", msg.ChannelId.String(),
	)
}

func Misbehaviour(_ realm, msg MsgMisbehaviour) {
	impl := st.getClient(msg.ClientId)
	impl.Misbehaviour(cross, msg.ClientId, msg.ClientMessage)
	chain.Emit(MisbehaviourEvent,
		"client_id", msg.ClientId.String(),
	)
}

func ChannelCloseInit(_ realm, msg MsgChannelCloseInit) {
	channel := st.getChannel(msg.ChannelId)
	if channel.State != ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)
	st.getAppByPortId(portId).OnChannelCloseInit(msg.ChannelId, msg.Relayer)
	channel.State = ChannelStateClosed
	st.saveChannel(msg.ChannelId, channel)
	chain.Emit(ChannelCloseInitEvent,
		"channel_id", msg.ChannelId.String(),
	)
}

func ChannelCloseConfirm(_ realm, msg MsgChannelCloseConfirm) {
	channel := st.getChannel(msg.ChannelId)
	if channel.State != ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)

	expectedChannel := Channel{
		State:                 ChannelStateClosed,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    Bytes(portId[:]),
		Version:               channel.Version,
	}
	key := ChannelPath(channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofClose, key[:], value[:])

	st.getAppByPortId(portId).OnChannelCloseConfirm(msg.ChannelId, msg.Relayer)
	channel.State = ChannelStateClosed
	st.saveChannel(msg.ChannelId, channel)
	chain.Emit(ChannelCloseConfirmEvent,
		"channel_id", msg.ChannelId.String(),
	)
}

func PacketSend(_ realm, msg MsgPacketSend) Packet {
	channel := st.getChannel(msg.SourceChannelId)
	if channel.State != ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}

	packet := Packet{
		SourceChannelId:      msg.SourceChannelId,
		DestinationChannelId: channel.CounterpartyChannelId,
		Data:                 msg.Data,
		TimeoutTimestamp:     msg.TimeoutTimestamp,
	}

	st.commitPacket(packet)

	chain.Emit(PacketSendEvent,
		"source_channel_id", packet.SourceChannelId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"timeout_timestamp", packet.TimeoutTimestamp.String(),
	)
	return packet
}

func PacketRecv(_ realm, msg MsgPacketRecv) {
	for i, packet := range msg.Packets {
		channel := st.getChannel(packet.DestinationChannelId)
		if channel.State != ChannelStateOpen {
			panic(ErrInvalidChannelState)
		}
		connection := ensureConnectionOpen(channel.ConnectionId)

		// Verify packet commitment on counterparty
		key := PacketCommitmentPath(Packet{
			SourceChannelId:      packet.SourceChannelId,
			DestinationChannelId: packet.DestinationChannelId,
			Data:                 packet.Data,
			TimeoutTimestamp:     packet.TimeoutTimestamp,
		})
		st.getClient(connection.ClientId).VerifyMembership(
			connection.ClientId, msg.ProofHeight, msg.Proof, key[:], COMMITMENT_MAGIC[:],
		)

		var relayerMsg Bytes
		if i < len(msg.RelayerMsgs) {
			relayerMsg = msg.RelayerMsgs[i]
		}
		portId := st.getChannelOwner(packet.DestinationChannelId)
		st.getAppByPortId(portId).OnRecvPacket(packet, msg.Relayer, relayerMsg)

		chain.Emit(PacketRecvEvent,
			"source_channel_id", packet.SourceChannelId.String(),
			"destination_channel_id", packet.DestinationChannelId.String(),
		)
	}
}

func PacketAcknowledgement(_ realm, msg MsgPacketAcknowledgement) {
	for i, packet := range msg.Packets {
		if !st.hasPacketCommitment(packet) {
			continue // no-op: already acknowledged or never sent
		}

		channel := st.getChannel(packet.SourceChannelId)
		connection := ensureConnectionOpen(channel.ConnectionId)

		ack := msg.Acknowledgements[i]
		key := PacketAcknowledgementPath(Packet{
			SourceChannelId:      packet.DestinationChannelId,
			DestinationChannelId: packet.SourceChannelId,
			Data:                 packet.Data,
			TimeoutTimestamp:     packet.TimeoutTimestamp,
		})
		value := keccak(ack)
		st.getClient(connection.ClientId).VerifyMembership(
			connection.ClientId, msg.ProofHeight, msg.Proof, key[:], value[:],
		)

		portId := st.getChannelOwner(packet.SourceChannelId)
		st.getAppByPortId(portId).OnAcknowledgementPacket(packet, ack, msg.Relayer)

		st.deletePacketCommitment(packet)

		chain.Emit(PacketAckEvent,
			"source_channel_id", packet.SourceChannelId.String(),
			"destination_channel_id", packet.DestinationChannelId.String(),
			"relayer", string(msg.Relayer),
		)
	}
}

func PacketTimeout(_ realm, msg MsgPacketTimeout) {
	packet := msg.Packet
	if !st.hasPacketCommitment(packet) {
		return // no-op
	}

	channel := st.getChannel(packet.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	// Verify non-membership of packet receipt on counterparty
	key := PacketCommitmentPath(Packet{
		SourceChannelId:      packet.DestinationChannelId,
		DestinationChannelId: packet.SourceChannelId,
		Data:                 packet.Data,
		TimeoutTimestamp:     packet.TimeoutTimestamp,
	})
	st.getClient(connection.ClientId).VerifyNonMembership(
		connection.ClientId, msg.ProofHeight, msg.Proof, key[:],
	)

	portId := st.getChannelOwner(packet.SourceChannelId)
	st.getAppByPortId(portId).OnTimeoutPacket(packet, msg.Relayer)

	st.deletePacketCommitment(packet)

	chain.Emit(PacketTimeoutEvent,
		"source_channel_id", packet.SourceChannelId.String(),
		"destination_channel_id", packet.DestinationChannelId.String(),
		"relayer", string(msg.Relayer),
	)
}

// CreateClientRaw is a convenience wrapper for testing: accepts hex-encoded bytes.
func CreateClientRaw(_ realm, clientType string, clientStateHex, consensusStateHex string) ClientId {
	csBytes, err := hex.DecodeString(clientStateHex)
	if err != nil {
		panic("invalid clientStateHex: " + err.Error())
	}
	consBytes, err := hex.DecodeString(consensusStateHex)
	if err != nil {
		panic("invalid consensusStateHex: " + err.Error())
	}
	return CreateClient(cross, MsgCreateClient{
		ClientType:          ClientType(clientType),
		ClientStateBytes:    csBytes,
		ConsensusStateBytes: consBytes,
	})
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
