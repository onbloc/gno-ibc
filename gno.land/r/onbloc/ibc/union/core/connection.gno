package core

import (
	"chain"

	"gno.land/p/onbloc/ibc/union/types"
)

func NewConnection(state types.ConnectionState, clientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) types.Connection {
	return types.Connection{State: state, ClientId: clientId, CounterpartyClientId: counterpartyClientId, CounterpartyConnectionId: counterpartyConnectionId}
}

func ConnectionOpenInit(_ realm, msg types.MsgConnectionOpenInit) types.ConnectionId {
	connectionId := store.nextConnectionId()
	store.saveConnection(connectionId, NewConnection(types.ConnectionStateInit, msg.ClientId, msg.CounterpartyClientId, 0))
	chain.Emit(ConnectionOpenInitEvent,
		"connection_id", connectionId.String(),
		"client_id", msg.ClientId.String(),
		"counterparty_client_id", msg.CounterpartyClientId.String(),
	)
	return connectionId
}

func ConnectionOpenTry(_ realm, msg types.MsgConnectionOpenTry) types.ConnectionId {
	connectionId := store.nextConnectionId()

	expectedConnection := NewConnection(types.ConnectionStateInit, msg.CounterpartyClientId, msg.ClientId, 0)
	key := types.ConnectionPath(msg.CounterpartyConnectionId)
	value := connectionValue(expectedConnection)
	verifyMembershipActive(msg.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])

	store.saveConnection(connectionId, NewConnection(types.ConnectionStateTryOpen, msg.ClientId, msg.CounterpartyClientId, msg.CounterpartyConnectionId))
	chain.Emit(ConnectionOpenTryEvent,
		"connection_id", connectionId.String(),
		"client_id", msg.ClientId.String(),
		"counterparty_client_id", msg.CounterpartyClientId.String(),
		"counterparty_connection_id", msg.CounterpartyConnectionId.String(),
	)
	return connectionId
}

func ConnectionOpenAck(_ realm, msg types.MsgConnectionOpenAck) {
	connection, ok := store.getConnection(msg.ConnectionId)
	if !ok {
		panic("connection " + msg.ConnectionId.String() + " not found")
	}
	if connection.State != types.ConnectionStateInit {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := NewConnection(types.ConnectionStateTryOpen, connection.CounterpartyClientId, connection.ClientId, msg.CounterpartyConnectionId)
	key := types.ConnectionPath(msg.CounterpartyConnectionId)
	value := connectionValue(expectedConnection)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofTry, key[:], value[:])

	connection.State = types.ConnectionStateOpen
	connection.CounterpartyConnectionId = msg.CounterpartyConnectionId
	store.saveConnection(msg.ConnectionId, connection)

	chain.Emit(ConnectionOpenAckEvent,
		"connection_id", msg.ConnectionId.String(),
		"client_id", connection.ClientId.String(),
		"counterparty_client_id", connection.CounterpartyClientId.String(),
		"counterparty_connection_id", msg.CounterpartyConnectionId.String(),
	)
}

func ConnectionOpenConfirm(_ realm, msg types.MsgConnectionOpenConfirm) {
	connection, ok := store.getConnection(msg.ConnectionId)
	if !ok {
		panic("connection " + msg.ConnectionId.String() + " not found")
	}
	if connection.State != types.ConnectionStateTryOpen {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := NewConnection(types.ConnectionStateOpen, connection.CounterpartyClientId, connection.ClientId, msg.ConnectionId)
	key := types.ConnectionPath(connection.CounterpartyConnectionId)
	value := connectionValue(expectedConnection)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofAck, key[:], value[:])

	connection.State = types.ConnectionStateOpen
	store.saveConnection(msg.ConnectionId, connection)

	chain.Emit(ConnectionOpenConfirmEvent,
		"connection_id", msg.ConnectionId.String(),
		"client_id", connection.ClientId.String(),
		"counterparty_client_id", connection.CounterpartyClientId.String(),
		"counterparty_connection_id", connection.CounterpartyConnectionId.String(),
	)
}

func QueryConnection(connectionId types.ConnectionId) string {
	connection, ok := store.getConnection(connectionId)
	if !ok {
		return ""
	}
	bz, err := connection.EncodeABI()
	if err != nil {
		return ""
	}
	return hexString(bz)
}

func ensureConnectionOpen(connectionId types.ConnectionId) types.Connection {
	connection, ok := store.getConnection(connectionId)
	if !ok {
		panic("connection " + connectionId.String() + " not found")
	}
	if connection.State != types.ConnectionStateOpen {
		panic(ErrInvalidConnectionState)
	}
	return connection
}
