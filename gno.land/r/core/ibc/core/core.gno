package core

import (
	// "chain/params"
	"chain"
	"errors"
)

var state State

var (
	ErrClientTypeAlreadyRegistered = errors.New("client type already registered")
	ErrClientNotFound              = errors.New("client not found")
	ErrConnectionNotFound          = errors.New("connection not found")
	ErrInvalidConnectionState      = errors.New("invalid connection state")
	ErrChannelNotFound             = errors.New("channel not found")
)

func init() {
	state = State{
		clientRegistry:  make(map[ClientType]ILightClient),
		clientTypes:     make(map[ClientId]ClientType),
		clientStates:    make(map[ClientId][]byte),
		consensusStates: make(map[ClientId]map[Height][]byte),
		connections:     make(map[ConnectionId]Connection),
		channels:        make(map[ChannelId]Channel),
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
	GetTimestamp(client_id ClientId, height Height) Timestamp

	// GetLatestHeight gets the latest trusted height of a client.
	GetLatestHeight(client_id ClientId) Height

	// GetStatus gets the status of a client.
	GetStatus(client_id ClientId) Status
}

type ConsensusStateUpdate struct {
	height              Height
	consensusStateBytes []byte
	clientStateBytes    []byte
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
	PacketRecvEvent            = "PacketRecv"
	WriteAckEvent              = "WriteAck"
	PacketAckEvent             = "PacketAck"
	PacketTimeoutEvent         = "PacketTimeout"
)

func keccak(bz []byte) (_ H256)       { return } // stub for now
func ethabi(i interface{}) (_ []byte) { return } // stub for now
func commit(key H256, value H256)     {}         // stub for now

func RegisterClient(
	_ realm,
	clientType ClientType,
	client ILightClient,
) {
	state.registerClient(clientType, client)
}

func CreateClient(
	_ realm,
	clientType ClientType,
	clientStateBytes []byte,
	consensusStateBytes []byte,
) ClientId {
	impl := state.clientRegistry[clientType]

	clientId := state.generateClientId()

	counterpartyChainId := impl.CreateClient(clientId, clientStateBytes, consensusStateBytes)

	state.clientTypes[clientId] = clientType

	chain.Emit(
		CreateClientEvent,
		"client_type", string(clientType),
		"client_id", clientId.String(),
		"counterparty_chain_id", counterpartyChainId,
	)

	return clientId
}

func UpdateClient(
	_ realm,
	clientId ClientId,
	clientMessage []byte,
) Height {
	impl := state.getClient(clientId)

	update := impl.UpdateClient(clientId, clientMessage)

	state.saveClientState(clientId, update.clientStateBytes)
	state.saveConsensusState(clientId, update.height, update.consensusStateBytes)

	chain.Emit(
		UpdateClientEvent,
		"client_id", clientId.String(),
		"height", update.height.String(),
	)

	return update.height
}

func ConnectionOpenInit(
	_ realm,
	clientId ClientId,
	counterpartyClientId ClientId,
) ConnectionId {
	connectionId := state.generateConnectionId()

	state.saveConnection(connectionId, Connection{
		state:                      ConnectionStateInit,
		client_id:                  clientId,
		counterparty_client_id:     counterpartyClientId,
		counterparty_connection_id: 0,
	})

	chain.Emit(
		ConnectionOpenInitEvent,
		"connection_id", connectionId.String(),
		"client_id", clientId.String(),
		"counterparty_client_id", counterpartyClientId.String(),
	)

	return connectionId
}

func ConnectionOpenTry(
	_ realm,
	clientId ClientId,
	counterpartyClientId ClientId,
	counterpartyConnectionId ConnectionId,
	proofInit []byte,
	proofHeight Height,
) ConnectionId {
	connectionId := state.generateConnectionId()

	expectedConnection := Connection{
		state:                      ConnectionStateInit,
		client_id:                  counterpartyClientId,
		counterparty_client_id:     clientId,
		counterparty_connection_id: 0,
	}

	key := ConnectionPath(counterpartyConnectionId)
	value := keccak(ethabi(expectedConnection))
	state.getClient(clientId).VerifyMembership(
		clientId,
		proofHeight,
		proofInit,
		key[:],
		value[:],
	)

	state.saveConnection(connectionId, Connection{
		state:                      ConnectionStateTryOpen,
		client_id:                  clientId,
		counterparty_client_id:     counterpartyClientId,
		counterparty_connection_id: counterpartyConnectionId,
	})

	chain.Emit(
		ConnectionOpenTryEvent,
		"connection_id", connectionId.String(),
		"client_id", clientId.String(),
		"counterparty_client_id", counterpartyClientId.String(),
		"counterparty_connection_id", counterpartyConnectionId.String(),
	)

	return connectionId
}

func ConnectionOpenAck(
	_ realm,
	connectionId ConnectionId,
	counterpartyConnectionId ConnectionId,
	proofTry []byte,
	proofHeight Height,
) ConnectionId {
	connection := state.getConnection(connectionId)

	if connection.state != ConnectionStateInit {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := Connection{
		state:                      ConnectionStateTryOpen,
		client_id:                  connection.counterparty_client_id,
		counterparty_client_id:     connection.client_id,
		counterparty_connection_id: connectionId,
	}

	key := ConnectionPath(counterpartyConnectionId)
	value := keccak(ethabi(expectedConnection))
	state.getClient(connection.client_id).VerifyMembership(
		connection.client_id,
		proofHeight,
		proofTry,
		key[:],
		value[:],
	)

	connection.state = ConnectionStateOpen
	connection.counterparty_connection_id = counterpartyConnectionId
	state.saveConnection(connectionId, connection)

	chain.Emit(
		ConnectionOpenAckEvent,
		"connection_id", connectionId.String(),
		"client_id", connection.client_id.String(),
		"counterparty_client_id", connection.counterparty_client_id.String(),
		"counterparty_connection_id", counterpartyConnectionId.String(),
	)

	return connectionId
}

func ConnectionOpenConfirm(
	_ realm,
	connectionId ConnectionId,
	proofAck []byte,
	proofHeight Height,
) ConnectionId {
	connection := state.getConnection(connectionId)

	if connection.state != ConnectionStateTryOpen {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := Connection{
		state:                      ConnectionStateOpen,
		client_id:                  connection.counterparty_client_id,
		counterparty_client_id:     connection.client_id,
		counterparty_connection_id: connectionId,
	}

	key := ConnectionPath(connection.counterparty_connection_id)
	value := keccak(ethabi(expectedConnection))
	state.getClient(connection.client_id).VerifyMembership(
		connection.client_id,
		proofHeight,
		proofAck,
		key[:],
		value[:],
	)

	connection.state = ConnectionStateOpen
	state.saveConnection(connectionId, connection)

	chain.Emit(
		ConnectionOpenConfirmEvent,
		"connection_id", connectionId.String(),
		"client_id", connection.client_id.String(),
		"counterparty_client_id", connection.counterparty_client_id.String(),
		"counterparty_connection_id", connection.counterparty_connection_id.String(),
	)

	return connectionId
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
