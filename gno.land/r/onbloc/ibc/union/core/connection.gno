package core

import (
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

func NewConnection(state types.ConnectionState, clientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) types.Connection {
	return types.Connection{State: state, ClientId: clientId, CounterpartyClientId: counterpartyClientId, CounterpartyConnectionId: counterpartyConnectionId}
}

func ConnectionOpenInit(cur realm, msg types.MsgConnectionOpenInit) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenInit, cur.Previous().Address())

	connectionId := store.nextConnectionId()

	connection := NewConnection(types.ConnectionStateInit, msg.ClientId, msg.CounterpartyClientId, 0)

	store.saveConnection(connectionId, connection)
	emitConnectionOpenInitEvent(connectionId, msg.ClientId, msg.CounterpartyClientId)
}

func ConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenTry, cur.Previous().Address())
	connectionOpenTry(msg, true)
}

func ForceConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	access.AssertCanCall(cross(cur), SelectorForceConnectionTry, cur.Previous().Address())
	connectionOpenTry(msg, false)
}

func connectionOpenTry(msg types.MsgConnectionOpenTry, verify bool) {
	connectionId := store.nextConnectionId()

	connection := NewConnection(types.ConnectionStateTryOpen, msg.ClientId, msg.CounterpartyClientId, msg.CounterpartyConnectionId)

	expectedConnection := NewConnection(types.ConnectionStateInit, msg.CounterpartyClientId, msg.ClientId, 0)

	if verify {
		key := types.ConnectionPath(msg.CounterpartyConnectionId)
		value := connectionValue(expectedConnection)
		verifyMembershipActive(msg.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])
	}

	store.saveConnection(connectionId, connection)
	emitConnectionOpenTryEvent(connectionId, msg.ClientId, msg.CounterpartyClientId, msg.CounterpartyConnectionId)
}

func ConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenAck, cur.Previous().Address())
	connectionOpenAck(msg, true)
}

func ForceConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	access.AssertCanCall(cross(cur), SelectorForceConnectionAck, cur.Previous().Address())
	connectionOpenAck(msg, false)
}

func connectionOpenAck(msg types.MsgConnectionOpenAck, verify bool) {
	connection, ok := store.getConnection(msg.ConnectionId)
	if !ok {
		panic("connection " + msg.ConnectionId.String() + " not found")
	}
	if connection.State != types.ConnectionStateInit {
		panic(ErrInvalidConnectionState)
	}

	if verify {
		expectedConnection := NewConnection(types.ConnectionStateTryOpen, connection.CounterpartyClientId, connection.ClientId, msg.ConnectionId)
		key := types.ConnectionPath(msg.CounterpartyConnectionId)
		value := connectionValue(expectedConnection)
		verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofTry, key[:], value[:])
	}

	connection.State = types.ConnectionStateOpen
	connection.CounterpartyConnectionId = msg.CounterpartyConnectionId
	store.saveConnection(msg.ConnectionId, connection)

	emitConnectionOpenAckEvent(msg.ConnectionId, connection.ClientId, connection.CounterpartyClientId, msg.CounterpartyConnectionId)
}

func ConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenConfirm, cur.Previous().Address())
	connectionOpenConfirm(msg, true)
}

func ForceConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	access.AssertCanCall(cross(cur), SelectorForceConnectionConfirm, cur.Previous().Address())
	connectionOpenConfirm(msg, false)
}

func connectionOpenConfirm(msg types.MsgConnectionOpenConfirm, verify bool) {
	connection, ok := store.getConnection(msg.ConnectionId)
	if !ok {
		panic("connection " + msg.ConnectionId.String() + " not found")
	}
	if connection.State != types.ConnectionStateTryOpen {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := NewConnection(types.ConnectionStateOpen, connection.CounterpartyClientId, connection.ClientId, msg.ConnectionId)

	counterpartyConnectionId := connection.CounterpartyConnectionId

	if verify {
		key := types.ConnectionPath(counterpartyConnectionId)
		value := connectionValue(expectedConnection)
		verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofAck, key[:], value[:])
	}

	connection.State = types.ConnectionStateOpen
	store.saveConnection(msg.ConnectionId, connection)

	emitConnectionOpenConfirmEvent(msg.ConnectionId, connection.ClientId, connection.CounterpartyClientId, counterpartyConnectionId)
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
