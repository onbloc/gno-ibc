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

// ChannelValue returns the H256 commitment value of a channel, exposed so the
// impl can build the expected counterparty value for membership proofs.
func ChannelValue(channel types.Channel) types.H256 {
	return channelValue(channel)
}

// EmitChannelOpenInit emits the ChannelOpenInit host event.
func EmitChannelOpenInit(portId types.Bytes, channelId types.ChannelId, channel types.Channel) {
	emitChannelOpenInitEvent(portId, channelId, channel)
}

// EmitChannelOpenTry emits the ChannelOpenTry host event.
func EmitChannelOpenTry(portId types.Bytes, channelId types.ChannelId, channel types.Channel, counterpartyVersion string) {
	emitChannelOpenTryEvent(portId, channelId, channel, counterpartyVersion)
}

// EmitChannelOpenAck emits the ChannelOpenAck host event.
func EmitChannelOpenAck(portId types.Bytes, channelId types.ChannelId, channel types.Channel) {
	emitChannelOpenAckEvent(portId, channelId, channel)
}

// EmitChannelOpenConfirm emits the ChannelOpenConfirm host event.
func EmitChannelOpenConfirm(portId types.Bytes, channelId types.ChannelId, channel types.Channel) {
	emitChannelOpenConfirmEvent(portId, channelId, channel)
}

// EmitChannelCloseInit emits the ChannelCloseInit host event.
func EmitChannelCloseInit(portId types.Bytes, channelId types.ChannelId, channel types.Channel) {
	emitChannelCloseInitEvent(portId, channelId, channel)
}

// EmitChannelCloseConfirm emits the ChannelCloseConfirm host event.
func EmitChannelCloseConfirm(portId types.Bytes, channelId types.ChannelId, channel types.Channel) {
	emitChannelCloseConfirmEvent(portId, channelId, channel)
}

// EmitAppRegistered emits the AppRegistered host event.
func EmitAppRegistered(portId []byte, registrarPkgPath string, adminOverride bool) {
	emitAppRegisteredEvent(portId, registrarPkgPath, adminOverride)
}
