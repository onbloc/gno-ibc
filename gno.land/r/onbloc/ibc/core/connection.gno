package core

import "chain"

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
	verifyMembershipActive(msg.ClientId, msg.ProofHeight, msg.ProofInit, key[:], value[:])

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
	verifyMembershipActive(connection.ClientId, msg.ProofHeight, msg.ProofTry, key[:], value[:])

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
	verifyMembershipActive(connection.ClientId, msg.ProofHeight, msg.ProofAck, key[:], value[:])

	connection.State = ConnectionStateOpen
	st.saveConnection(msg.ConnectionId, connection)

	chain.Emit(ConnectionOpenConfirmEvent,
		"connection_id", msg.ConnectionId.String(),
		"client_id", connection.ClientId.String(),
		"counterparty_client_id", connection.CounterpartyClientId.String(),
		"counterparty_connection_id", connection.CounterpartyConnectionId.String(),
	)
}

func QueryConnection(connectionId ConnectionId) string {
	connection, ok := st.connections[connectionId]
	if !ok {
		return ""
	}
	return hexString(connection.EthAbiEncode())
}

func ensureConnectionOpen(connectionId ConnectionId) Connection {
	connection := st.getConnection(connectionId)
	if connection.State != ConnectionStateOpen {
		panic(ErrInvalidConnectionState)
	}
	return connection
}
