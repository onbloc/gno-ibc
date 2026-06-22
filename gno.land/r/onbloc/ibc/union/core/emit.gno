package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

// emit.gno exposes the host event emitters the injected impl calls so that
// events are emitted from the core (proxy) realm, keeping the IBC host as the
// stable event source across impl upgrades. Mirrors EmitRecvError used by the

// EmitRegisterClient emits the RegisterClient host event.
func EmitRegisterClient(clientType types.ClientType) {
	emitRegisterClientEvent(clientType)
}

// EmitCreateClient emits the CreateClient host event.
func EmitCreateClient(clientId types.ClientId, clientType types.ClientType, counterpartyChainId string) {
	emitCreateClientEvent(clientId, clientType, counterpartyChainId)
}

// EmitUpdateClient emits the UpdateClient host event.
func EmitUpdateClient(clientId types.ClientId, height types.Height) {
	emitUpdateClientEvent(clientId, height)
}

// EmitForceUpdateClient emits the ForceUpdateClient host event.
func EmitForceUpdateClient(clientId types.ClientId, height types.Height) {
	emitForceUpdateClientEvent(clientId, height)
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

// --- Packet lifecycle: pure helpers and event emitters exposed to the impl ---

// CommitPacketHash returns the union commitment hash of a single packet.
func CommitPacketHash(packet types.Packet) types.H256 {
	return commitPacketHash(packet)
}

// CommitPacketsHash returns the union commitment hash of a packet batch.
func CommitPacketsHash(packets []types.Packet) types.H256 {
	return commitPacketsHash(packets)
}

// NowNanos returns the current block time in nanoseconds (the recv-timeout clock).
func NowNanos() uint64 {
	return nowNanos()
}

// EmitPacketSend emits the PacketSend host event.
func EmitPacketSend(packet types.Packet, sourceChannel types.Channel, sourceConnection types.Connection) {
	emitPacketSendEvent(packet, sourceChannel, sourceConnection)
}

// EmitPacketRecv emits the PacketRecv host event.
func EmitPacketRecv(packet types.Packet, channel types.Channel, connection types.Connection, relayerMsg []byte) {
	emitPacketRecvEvent(PacketRecvEvent, packet, channel, connection, "maker_msg", relayerMsg)
}

// EmitIntentPacketRecv emits the IntentPacketRecv host event.
func EmitIntentPacketRecv(packet types.Packet, channel types.Channel, connection types.Connection, marketMakerMsg []byte) {
	emitPacketRecvEvent(IntentPacketRecvEvent, packet, channel, connection, "market_maker_msg", marketMakerMsg)
}

// EmitPacketAck emits the PacketAck host event.
func EmitPacketAck(packet types.Packet, sourceChannel types.Channel, connection types.Connection, acknowledgement []byte) {
	emitPacketAckEvent(packet, sourceChannel, connection, acknowledgement)
}

// EmitPacketTimeout emits the PacketTimeout host event.
func EmitPacketTimeout(packet types.Packet, sourceChannel types.Channel, connection types.Connection) {
	emitPacketTimeoutEvent(packet, sourceChannel, connection)
}

// EmitWriteAck emits the WriteAck host event.
func EmitWriteAck(channelId types.ChannelId, packet types.Packet, acknowledgement []byte) {
	emitWriteAckEvent(channelId, packet, acknowledgement)
}

// EmitBatchSend emits the BatchSend host event.
func EmitBatchSend(channelId types.ChannelId, packetHash, batchHash types.H256) {
	emitBatchSendEvent(channelId, packetHash, batchHash)
}

// EmitBatchAcks emits the BatchAcks host event.
func EmitBatchAcks(channelId types.ChannelId, packetHash, batchHash types.H256) {
	emitBatchAcksEvent(channelId, packetHash, batchHash)
}

// EmitCommitMembershipProof emits the CommitMembershipProof host event.
func EmitCommitMembershipProof(msg types.MsgCommitMembershipProof) {
	emitCommitMembershipProofEvent(msg)
}

// EmitCommitNonMembershipProof emits the CommitNonMembershipProof host event.
func EmitCommitNonMembershipProof(msg types.MsgCommitNonMembershipProof) {
	emitCommitNonMembershipProofEvent(msg)
}
