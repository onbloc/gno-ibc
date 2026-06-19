package core

import (
	"chain"

	"gno.land/p/onbloc/ibc/union/types"
)

// emit.gno exposes the host event emitters the injected impl calls so that
// events are emitted from the core (proxy) realm, keeping the IBC host as the
// stable event source across impl upgrades. Mirrors EmitRecvError used by the
// ucs03_zkgm impl.

// EmitCreateClient emits the CreateClient host event.
func EmitCreateClient(clientId types.ClientId, clientType types.ClientType) {
	chain.Emit(
		CreateClientEvent,
		"client_id", clientId.String(),
		"client_type", clientType.String(),
	)
}

// EmitUpdateClient emits the UpdateClient host event.
func EmitUpdateClient(clientType types.ClientType, clientId types.ClientId, height types.Height) {
	chain.Emit(
		UpdateClientEvent,
		"client_type", clientType.String(),
		"client_id", clientId.String(),
		"height", height.String(),
	)
}

// EmitConnectionOpenInit emits the ConnectionOpenInit host event.
func EmitConnectionOpenInit(connectionId types.ConnectionId, clientId, counterpartyClientId types.ClientId) {
	emitConnectionOpenInitEvent(connectionId, clientId, counterpartyClientId)
}

// EmitConnectionOpenTry emits the ConnectionOpenTry host event.
func EmitConnectionOpenTry(connectionId types.ConnectionId, clientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) {
	emitConnectionOpenTryEvent(connectionId, clientId, counterpartyClientId, counterpartyConnectionId)
}

// EmitConnectionOpenAck emits the ConnectionOpenAck host event.
func EmitConnectionOpenAck(connectionId types.ConnectionId, clientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) {
	emitConnectionOpenAckEvent(connectionId, clientId, counterpartyClientId, counterpartyConnectionId)
}

// EmitConnectionOpenConfirm emits the ConnectionOpenConfirm host event.
func EmitConnectionOpenConfirm(connectionId types.ConnectionId, clientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) {
	emitConnectionOpenConfirmEvent(connectionId, clientId, counterpartyClientId, counterpartyConnectionId)
}

// ConnectionValue returns the H256 commitment value of a connection, exposed so
// the impl can build the expected counterparty value for membership proofs.
func ConnectionValue(connection types.Connection) types.H256 {
	return connectionValue(connection)
}
