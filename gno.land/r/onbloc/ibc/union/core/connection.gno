package core

import (
	"chain"

	"gno.land/p/onbloc/ibc/union/types"
)

func ConnectionOpenInit(_ realm, msg types.MsgConnectionOpenInit) types.ConnectionId {
	requireClientId(msg.ClientId)
	requireClientId(msg.CounterpartyClientId)
	requireActiveClient(st.getClient(msg.ClientId), msg.ClientId)
	st.saveConnection(connectionId, types.Connection{
		State:                    types.ConnectionStateInit,
		ClientId:                 msg.ClientId,
		CounterpartyClientId:     msg.CounterpartyClientId,
		CounterpartyConnectionId: 0,
	})

	connectionId := st.generateConnectionId()
	chain.Emit(ConnectionOpenInitEvent,
		"connection_id", connectionId.String(),
		"client_id", msg.ClientId.String(),
		"counterparty_client_id", msg.CounterpartyClientId.String(),
	)
	return connectionId
}

func ConnectionOpenTry(_ realm, msg types.MsgConnectionOpenTry) types.ConnectionId {
	requireClientId(msg.ClientId)
	requireClientId(msg.CounterpartyClientId)
	requireConnectionId(msg.CounterpartyConnectionId)

	expectedConnection := types.Connection{
		State:                    types.ConnectionStateInit,
		ClientId:                 msg.CounterpartyClientId,
		CounterpartyClientId:     msg.ClientId,
		CounterpartyConnectionId: 0,
	}
	key := types.ConnectionPath(msg.CounterpartyConnectionId)
	value := connectionValue(expectedConnection)
	verifyMembershipActive(msg.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])

	connectionId := st.generateConnectionId()
	st.saveConnection(connectionId, types.Connection{
		State:                    types.ConnectionStateTryOpen,
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

func ConnectionOpenAck(_ realm, msg types.MsgConnectionOpenAck) {
	requireConnectionId(msg.ConnectionId)
	requireConnectionId(msg.CounterpartyConnectionId)
	connection := st.getConnection(msg.ConnectionId)
	if connection.State != types.ConnectionStateInit {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := types.Connection{
		State:                    types.ConnectionStateTryOpen,
		ClientId:                 connection.CounterpartyClientId,
		CounterpartyClientId:     connection.ClientId,
		CounterpartyConnectionId: msg.ConnectionId,
	}
	key := types.ConnectionPath(msg.CounterpartyConnectionId)
	value := connectionValue(expectedConnection)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofTry, key[:], value[:])

	connection.State = types.ConnectionStateOpen
	connection.CounterpartyConnectionId = msg.CounterpartyConnectionId
	st.saveConnection(msg.ConnectionId, connection)

	chain.Emit(ConnectionOpenAckEvent,
		"connection_id", msg.ConnectionId.String(),
		"client_id", connection.ClientId.String(),
		"counterparty_client_id", connection.CounterpartyClientId.String(),
		"counterparty_connection_id", msg.CounterpartyConnectionId.String(),
	)
}

func ConnectionOpenConfirm(_ realm, msg types.MsgConnectionOpenConfirm) {
	requireConnectionId(msg.ConnectionId)
	connection := st.getConnection(msg.ConnectionId)
	if connection.State != types.ConnectionStateTryOpen {
		panic(ErrInvalidConnectionState)
	}

	expectedConnection := types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 connection.CounterpartyClientId,
		CounterpartyClientId:     connection.ClientId,
		CounterpartyConnectionId: msg.ConnectionId,
	}
	key := types.ConnectionPath(connection.CounterpartyConnectionId)
	value := connectionValue(expectedConnection)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofAck, key[:], value[:])

	connection.State = types.ConnectionStateOpen
	st.saveConnection(msg.ConnectionId, connection)

	chain.Emit(ConnectionOpenConfirmEvent,
		"connection_id", msg.ConnectionId.String(),
		"client_id", connection.ClientId.String(),
		"counterparty_client_id", connection.CounterpartyClientId.String(),
		"counterparty_connection_id", connection.CounterpartyConnectionId.String(),
	)
}

func QueryConnection(connectionId types.ConnectionId) string {
	connection, ok := st.connections[connectionId]
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
	connection := st.getConnection(connectionId)
	if connection.State != types.ConnectionStateOpen {
		panic(ErrInvalidConnectionState)
	}
	return connection
}
