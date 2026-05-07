package core

import (
	"chain"
	"chain/params"
	"crypto/keccak256"
	"errors"
)

var state State

var (
	ErrClientTypeAlreadyRegistered = errors.New("client type already registered")
	ErrClientTypeNotFound          = errors.New("client type not found")
	ErrClientNotFound              = errors.New("client not found")
	ErrConnectionNotFound          = errors.New("connection not found")
	ErrInvalidConnectionState      = errors.New("invalid connection state")
	ErrChannelNotFound             = errors.New("channel not found")
	ErrInvalidChannelState         = errors.New("invalid channel state")
	ErrPortNotFound                = errors.New("port not found")
)

func init() {
	state = State{
		nextClientId:     ClientId(1),
		nextConnectionId: ConnectionId(1),
		nextChannelId:    ChannelId(1),
		clientRegistry:   make(map[ClientType]ILightClient),
		clientTypes:      make(map[ClientId]ClientType),
		connections:      make(map[ConnectionId]Connection),
		channels:         make(map[ChannelId]Channel),
	}
}

// ILightClient defines the required functionality for a light client.
//
// All methods are expected to panic on error.
// REVIEW: Is panic best here? Or should we do more traditional error handling?
type ILightClient interface {
	// CreateClient creates a new client with the given TOFU states.
	CreateClient(clientId ClientId, clientStateBytes, consensusStateBytes []byte) string

	// UpdateClient updates a client with the given client message.
	UpdateClient(clientId ClientId, clientMessage []byte) ConsensusStateUpdate

	// Misbehaviour checks for misbehaviour on the counterparty chain tracked by clientId, returning the newly frozen client state if the misbehaviour is valid.
	Misbehaviour(clientId ClientId, clientMessage []byte) []byte

	// VerifyMembership verifies an inclusion proof against a client's trusted state at a given height for a given key and value.
	VerifyMembership(clientId ClientId, height Height, proof []byte, key []byte, value []byte)

	// VerifyNonMembership verifies an exclusion proof against a client's trusted state at a given height for a given key.
	VerifyNonMembership(clientId ClientId, height Height, proof []byte, key []byte)

	// GetTimestamp gets the timestamp of a client at a specific height.
	GetTimestamp(clientId ClientId, height Height) Timestamp

	// GetLatestHeight gets the latest trusted height of a client.
	GetLatestHeight(clientId ClientId) Height

	// GetStatus gets the status of a client.
	GetStatus(clientId ClientId) Status
}

type IApp interface {
	OnChannelOpenInit(connectionId ConnectionId, channelId ChannelId, version string, relayer address)
	OnChannelOpenTry(connectionId ConnectionId, channelId ChannelId, version string, counterpartyVersion string, relayer address)
	OnChannelOpenAck(channelId ChannelId, counterpartyChannelId ChannelId, counterpartyVersion string, relayer address)
	OnChannelOpenConfirm(channelId ChannelId, relayer address)
	OnChannelCloseInit(channelId ChannelId, relayer address)
	OnChannelCloseConfirm(channelId ChannelId, relayer address)
	OnIntentRecvPacket(packet Packet, marketMaker string, marketMakerMsg Bytes)
	OnRecvPacket(packet Packet, relayer address, relayerMsg Bytes)
	OnAcknowledgementPacket(packet Packet, acknowledgement Bytes, relayer address)
	OnTimeoutPacket(packet Packet, relayer address)
}

// TODO: Move to a /p/ package
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
	PacketRecvEvent            = "PacketRecv"
	WriteAckEvent              = "WriteAck"
	PacketAckEvent             = "PacketAck"
	PacketTimeoutEvent         = "PacketTimeout"
)

func keccak(bz []byte) (_ H256) {
	return keccak256.Sum256(bz)
}

func commit(key H256, value H256) {
	params.SetBytes(string(key[:]), value[:])
}

func RegisterClient(
	_ realm,
	clientType ClientType,
	client ILightClient,
) {
	state.registerClient(clientType, client)
}

func CreateClient(_ realm, msg MsgCreateClient) ClientId {
	impl := state.clientRegistry[msg.ClientType]

	clientId := state.generateClientId()

	counterpartyChainId := impl.CreateClient(clientId, msg.ClientStateBytes, msg.ConsensusStateBytes)

	state.clientTypes[clientId] = msg.ClientType

	chain.Emit(
		CreateClientEvent,
		"client_type", string(msg.ClientType),
		"client_id", clientId.String(),
		"counterparty_chain_id", counterpartyChainId,
	)

	return clientId
}

func UpdateClient(_ realm, msg MsgUpdateClient) Height {
	impl := state.getClient(msg.ClientId)

	update := impl.UpdateClient(msg.ClientId, msg.ClientMessage)

	state.saveClientState(msg.ClientId, update.ClientStateBytes)
	state.saveConsensusState(msg.ClientId, update.Height, update.ConsensusStateBytes)

	chain.Emit(
		UpdateClientEvent,
		"client_id", msg.ClientId.String(),
		"height", update.Height.String(),
	)

	return update.Height
}

func ConnectionOpenInit(_ realm, msg MsgConnectionOpenInit) ConnectionId {
	connectionId := state.generateConnectionId()

	state.saveConnection(connectionId, Connection{
		State:                    ConnectionStateInit,
		ClientId:                 msg.ClientId,
		CounterpartyClientId:     msg.CounterpartyClientId,
		CounterpartyConnectionId: 0, // not yet known, will be filled at ack
	})

	chain.Emit(
		ConnectionOpenInitEvent,
		"connection_id", connectionId.String(),
		"client_id", msg.ClientId.String(),
		"counterparty_client_id", msg.CounterpartyClientId.String(),
	)

	return connectionId
}

func ConnectionOpenTry(_ realm, msg MsgConnectionOpenTry) ConnectionId {
	connectionId := state.generateConnectionId()

	expectedConnection := Connection{
		State:                    ConnectionStateInit,
		ClientId:                 msg.CounterpartyClientId,
		CounterpartyClientId:     msg.ClientId,
		CounterpartyConnectionId: 0,
	}

	key := ConnectionPath(msg.CounterpartyConnectionId)
	value := keccak(expectedConnection.EthAbiEncode())
	state.getClient(msg.ClientId).VerifyMembership(
		msg.ClientId,
		msg.ProofHeight,
		msg.ProofInit,
		key[:],
		value[:],
	)

	state.saveConnection(connectionId, Connection{
		State:                    ConnectionStateTryOpen,
		ClientId:                 msg.ClientId,
		CounterpartyClientId:     msg.CounterpartyClientId,
		CounterpartyConnectionId: msg.CounterpartyConnectionId,
	})

	chain.Emit(
		ConnectionOpenTryEvent,
		"connection_id", connectionId.String(),
		"ClientId", msg.ClientId.String(),
		"counterpartyClientId", msg.CounterpartyClientId.String(),
		"CounterpartyConnectionId", msg.CounterpartyConnectionId.String(),
	)

	return connectionId
}

func ConnectionOpenAck(_ realm, msg MsgConnectionOpenAck) {
	connection := state.getConnection(msg.ConnectionId)

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
	state.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId,
		msg.ProofHeight,
		msg.ProofTry,
		key[:],
		value[:],
	)

	connection.State = ConnectionStateOpen
	connection.CounterpartyConnectionId = msg.CounterpartyConnectionId
	state.saveConnection(msg.ConnectionId, connection)

	chain.Emit(
		ConnectionOpenAckEvent,
		"connection_id", msg.ConnectionId.String(),
		"ClientId", connection.ClientId.String(),
		"counterpartyClientId", connection.CounterpartyClientId.String(),
		"CounterpartyConnectionId", msg.CounterpartyConnectionId.String(),
	)
}

func ConnectionOpenConfirm(_ realm, msg MsgConnectionOpenConfirm) {
	connection := state.getConnection(msg.ConnectionId)

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
	state.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId,
		msg.ProofHeight,
		msg.ProofAck,
		key[:],
		value[:],
	)

	connection.State = ConnectionStateOpen
	state.saveConnection(msg.ConnectionId, connection)

	chain.Emit(
		ConnectionOpenConfirmEvent,
		"connection_id", msg.ConnectionId.String(),
		"ClientId", connection.ClientId.String(),
		"counterpartyClientId", connection.CounterpartyClientId.String(),
		"CounterpartyConnectionId", connection.CounterpartyConnectionId.String(),
	)
}

func ChannelOpenInit(_ realm, msg MsgChannelOpenInit) ChannelId {
	ensureConnectionState(msg.ConnectionId)

	channelId := state.generateChannelId()

	state.channelOwners[channelId] = msg.PortId

	state.getAppByPortId(msg.PortId).OnChannelOpenInit(
		msg.ConnectionId,
		channelId,
		msg.Version,
		msg.Relayer,
	)

	state.saveChannel(channelId, Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0, // not yet known, will be filled in at ack
		CounterpartyPortId:    Bytes(msg.CounterpartyPortId),
		Version:               msg.Version,
	})

	chain.Emit(
		ChannelOpenInitEvent,
		"port_id", msg.PortId.String(),
		"channel_id", channelId.String(),
		"counterparty_port_id", msg.CounterpartyPortId.String(),
		"connection_id", msg.ConnectionId.String(),
		"version", msg.Version,
	)

	return channelId
}

func ChannelOpenTry(_ realm, msg MsgChannelOpenTry) ChannelId {
	if msg.Channel.State != ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}

	connection := ensureConnectionState(msg.Channel.ConnectionId)

	channelId := state.generateChannelId()

	expectedChannel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.Channel.ConnectionId,
		CounterpartyChannelId: 0, // not yet known, will be filled in at ack
		CounterpartyPortId:    Bytes(msg.PortId),
		Version:               msg.Channel.Version,
	}

	key := ChannelPath(msg.Channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	state.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId,
		msg.ProofHeight,
		msg.ProofInit,
		key[:],
		value[:],
	)

	state.channelOwners[channelId] = msg.PortId

	state.getAppByPortId(msg.PortId).OnChannelOpenTry(
		msg.Channel.ConnectionId,
		channelId,
		msg.Channel.Version,
		msg.CounterpartyVersion,
		msg.Relayer,
	)

	state.saveChannel(channelId, msg.Channel)

	chain.Emit(
		ChannelOpenTryEvent,
		"port_id", msg.PortId.String(),
		"channel_id", channelId.String(),
		"counterparty_port_id", msg.Channel.CounterpartyPortId.String(),
		"connection_id", msg.Channel.ConnectionId.String(),
		"version", msg.Channel.Version,
	)

	return channelId
}

func ChannelOpenAck(_ realm, msg MsgChannelOpenAck) {
	channel := state.getChannel(msg.ChannelId)

	if channel.State != ChannelStateInit {
		panic(ErrInvalidChannelState)
	}

	connection := ensureConnectionState(channel.ConnectionId)

	portId := state.getChannelOwner(msg.ChannelId)

	expectedChannel := Channel{
		State:                 ChannelStateTryOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    Bytes(portId),
		Version:               msg.CounterpartyVersion,
	}

	key := ChannelPath(msg.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	state.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId,
		msg.ProofHeight,
		msg.ProofTry,
		key[:],
		value[:],
	)

	state.getAppByPortId(portId).OnChannelOpenAck(
		msg.ChannelId,
		channel.CounterpartyChannelId,
		msg.CounterpartyVersion,
		msg.Relayer,
	)

	channel.State = ChannelStateOpen
	channel.Version = msg.CounterpartyVersion
	channel.CounterpartyChannelId = msg.CounterpartyChannelId

	state.saveChannel(msg.ChannelId, channel)

	chain.Emit(
		ChannelOpenAckEvent,
		"port_id", portId.String(),
		"channel_id", msg.ChannelId.String(),
		"counterparty_port_id", channel.CounterpartyPortId.String(),
		"counterparty_channel_id", channel.CounterpartyChannelId.String(),
		"connection_id", channel.ConnectionId.String(),
		"counterparty_version", msg.CounterpartyVersion,
	)
}

func ChannelOpenConfirm(_ realm, msg MsgChannelOpenConfirm) {
	channel := state.getChannel(msg.ChannelId)

	if channel.State != ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}

	connection := ensureConnectionState(channel.ConnectionId)

	portId := state.getChannelOwner(msg.ChannelId)

	expectedChannel := Channel{
		State:                 ChannelStateOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    Bytes(portId),
		Version:               channel.Version,
	}

	key := ChannelPath(channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	state.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId,
		msg.ProofHeight,
		msg.ProofAck,
		key[:],
		value[:],
	)

	state.getAppByPortId(portId).OnChannelOpenConfirm(msg.ChannelId, msg.Relayer)

	channel.State = ChannelStateOpen

	state.saveChannel(msg.ChannelId, channel)

	chain.Emit(
		ChannelOpenConfirmEvent,
		"port_id", portId.String(),
		"channel_id", msg.ChannelId.String(),
		"counterparty_port_id", channel.CounterpartyPortId.String(),
		"counterparty_channel_id", channel.CounterpartyChannelId.String(),
		"connection_id", channel.ConnectionId.String(),
	)
}

func ensureConnectionState(connectionId ConnectionId) Connection {
	connection := state.getConnection(connectionId)
	if connection.State != ConnectionStateOpen {
		panic(ErrInvalidConnectionState)
	} else {
		return connection
	}
}

func Render(_ string) string {
	s := ""

	s += "next client id: "
	s += state.nextClientId.String()

	s += "\n\n"

	s += "registered clients: ["

	for key := range state.clientRegistry {
		s += " "
		s += string(key)
	}

	s += " ]"

	return s
}
