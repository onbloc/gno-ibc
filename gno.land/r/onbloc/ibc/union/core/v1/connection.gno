package impl

import (
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// connection.gno: the connection handshake logic. The admin gate stays on the
// proxy entrypoint; this realm holds the protocol logic. The Force* recovery
// variants (no proof verification) remain on the proxy as admin operations.

// ConnectionOpenInit starts a connection in the Init state.
func (c *coreV1) ConnectionOpenInit(_ int, rlm realm, msg types.MsgConnectionOpenInit) {
	connectionId := c.store.NextConnectionId(0, rlm)
	connection := core.NewConnection(types.ConnectionStateInit, msg.ClientId, msg.CounterpartyClientId, 0)
	c.store.SaveConnection(0, rlm, connectionId, connection)
	core.EmitConnectionOpenInit(connectionId, msg.ClientId, msg.CounterpartyClientId)
}

// ConnectionOpenTry acknowledges a counterparty Init by proving it and moving to
// TryOpen.
func (c *coreV1) ConnectionOpenTry(_ int, rlm realm, msg types.MsgConnectionOpenTry) {
	connectionId := c.store.NextConnectionId(0, rlm)
	connection := core.NewConnection(types.ConnectionStateTryOpen, msg.ClientId, msg.CounterpartyClientId, msg.CounterpartyConnectionId)

	expectedConnection := core.NewConnection(types.ConnectionStateInit, msg.CounterpartyClientId, msg.ClientId, 0)
	key := types.ConnectionPath(msg.CounterpartyConnectionId)
	value := core.ConnectionValue(expectedConnection)
	c.verifyMembership(msg.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])

	c.store.SaveConnection(0, rlm, connectionId, connection)
	core.EmitConnectionOpenTry(connectionId, msg.ClientId, msg.CounterpartyClientId, msg.CounterpartyConnectionId)
}

// ConnectionOpenAck proves the counterparty TryOpen and moves the local Init
// connection to Open.
func (c *coreV1) ConnectionOpenAck(_ int, rlm realm, msg types.MsgConnectionOpenAck) {
	connection, ok := c.store.GetConnection(msg.ConnectionId)
	if !ok {
		panic("connection " + msg.ConnectionId.String() + " not found")
	}
	if connection.State != types.ConnectionStateInit {
		panic(core.ErrInvalidConnectionState)
	}

	expectedConnection := core.NewConnection(types.ConnectionStateTryOpen, connection.CounterpartyClientId, connection.ClientId, msg.ConnectionId)
	key := types.ConnectionPath(msg.CounterpartyConnectionId)
	value := core.ConnectionValue(expectedConnection)
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofTry, key[:], value[:])

	// Build a fresh connection rather than mutating the store-owned one (the
	// retrieved value is read-only under the borrow rule).
	updated := core.NewConnection(types.ConnectionStateOpen, connection.ClientId, connection.CounterpartyClientId, msg.CounterpartyConnectionId)
	c.store.SaveConnection(0, rlm, msg.ConnectionId, updated)

	core.EmitConnectionOpenAck(msg.ConnectionId, connection.ClientId, connection.CounterpartyClientId, msg.CounterpartyConnectionId)
}

// ConnectionOpenConfirm proves the counterparty Open and moves the local TryOpen
// connection to Open.
func (c *coreV1) ConnectionOpenConfirm(_ int, rlm realm, msg types.MsgConnectionOpenConfirm) {
	connection, ok := c.store.GetConnection(msg.ConnectionId)
	if !ok {
		panic("connection " + msg.ConnectionId.String() + " not found")
	}
	if connection.State != types.ConnectionStateTryOpen {
		panic(core.ErrInvalidConnectionState)
	}

	expectedConnection := core.NewConnection(types.ConnectionStateOpen, connection.CounterpartyClientId, connection.ClientId, msg.ConnectionId)
	counterpartyConnectionId := connection.CounterpartyConnectionId
	key := types.ConnectionPath(counterpartyConnectionId)
	value := core.ConnectionValue(expectedConnection)
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofAck, key[:], value[:])

	// Build a fresh connection rather than mutating the store-owned one.
	updated := core.NewConnection(types.ConnectionStateOpen, connection.ClientId, connection.CounterpartyClientId, counterpartyConnectionId)
	c.store.SaveConnection(0, rlm, msg.ConnectionId, updated)

	core.EmitConnectionOpenConfirm(msg.ConnectionId, connection.ClientId, connection.CounterpartyClientId, counterpartyConnectionId)
}

// ensureConnectionOpen returns the connection for connectionId, requiring it to
// be Open.
func (c *coreV1) ensureConnectionOpen(connectionId types.ConnectionId) types.Connection {
	connection, ok := c.store.GetConnection(connectionId)
	if !ok {
		panic("connection " + connectionId.String() + " not found")
	}

	if connection.State != types.ConnectionStateOpen {
		panic(core.ErrInvalidConnectionState)
	}

	return connection
}
