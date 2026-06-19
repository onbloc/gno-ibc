package core

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// types.gno declares the upgradeable-proxy contracts for the IBC host, mirroring
// the apps/ucs03_zkgm split. core is the proxy: it owns the stable identity
// (admin, package address/path), the Store, and the app registry, and delegates
// its logic to the installed impl.
//
// ICore is the swappable logic surface: it carries every non-admin entrypoint
// (client, connection, channel, packet, app registration). The admin/recovery
// entrypoints (SetAdmin, the Force* handshake overrides, RegisterAppForPort) and
// the read-only queries stay on the proxy — admin authority is not swappable, and
// queries are pure views.
//
// Migration is incremental: the client subsystem is implemented in core/v1; the
// remaining methods are present on ICore and stubbed in the impl until migrated.
type ICore interface {
	// SetStore injects the proxy-owned store. UpdateImpl calls it at install time
	// so the store stays private to the proxy (no public store getter).
	SetStore(_ int, rlm realm, store IStore)

	// --- Client ---
	CreateClient(_ int, rlm realm, clientType types.ClientType, lc lightclient.Interface) types.ClientId
	UpdateClient(_ int, rlm realm, msg types.MsgUpdateClient) types.Height
	VerifyClientMembership(_ int, rlm realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte)

	// --- Connection handshake ---
	ConnectionOpenInit(_ int, rlm realm, msg types.MsgConnectionOpenInit)
	ConnectionOpenTry(_ int, rlm realm, msg types.MsgConnectionOpenTry)
	ConnectionOpenAck(_ int, rlm realm, msg types.MsgConnectionOpenAck)
	ConnectionOpenConfirm(_ int, rlm realm, msg types.MsgConnectionOpenConfirm)

	// --- Channel handshake ---
	ChannelOpenInit(_ int, rlm realm, msg types.MsgChannelOpenInit) types.ChannelId
	ChannelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry) types.ChannelId
	ChannelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck)
	ChannelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm)
	ChannelCloseInit(_ int, rlm realm, msg types.MsgChannelCloseInit)
	ChannelCloseConfirm(_ int, rlm realm, msg types.MsgChannelCloseConfirm)

	// --- Packet lifecycle ---
	SendPacket(_ int, rlm realm, sourceChannelId types.ChannelId, timeoutTimestamp types.Timestamp, data []byte) types.Packet
	PacketRecv(_ int, rlm realm, msg types.MsgPacketRecv)
	IntentPacketRecv(_ int, rlm realm, msg types.MsgIntentPacketRecv)
	PacketAcknowledgement(_ int, rlm realm, msg types.MsgPacketAcknowledgement)
	PacketTimeout(_ int, rlm realm, msg types.MsgPacketTimeout)
	CommitMembershipProof(_ int, rlm realm, msg types.MsgCommitMembershipProof)
	CommitNonMembershipProof(_ int, rlm realm, msg types.MsgCommitNonMembershipProof)
	BatchSend(_ int, rlm realm, msg types.MsgBatchSend)
	BatchAcks(_ int, rlm realm, msg types.MsgBatchAcks)
	WriteAcknowledgement(_ int, rlm realm, msg types.MsgWriteAcknowledgement)

	// --- App registry ---
	RegisterApp(_ int, rlm realm, app app.IApp)
}

// IStore is the proxy-owned persistent state injected into the impl. Setters take
// the borrow-rule (_ int, rlm realm, ...) form; getters are plain. The nested
// per-client structure (consensus/connection/channel/batch trees, chain-param
// commitment mirror) stays private to the Store — the impl operates by id, so the
// encapsulation survives impl upgrades.
//
// IStore grows with the impl: it currently exposes the client subsystem; the
// connection/channel/packet/app operations are added as those subsystems migrate.
type IStore interface {
	// --- Client ---
	AddClient(_ int, rlm realm, typ types.ClientType, creator address, lc lightclient.Interface) types.ClientId
	ClientExists(clientId types.ClientId) bool
	ClientType(clientId types.ClientId) (types.ClientType, bool)
	GetLightClient(clientId types.ClientId) (lightclient.Interface, bool)
	SetLightClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) bool
	SaveClientState(_ int, rlm realm, clientId types.ClientId, clientStateBytes []byte) bool
	SaveConsensusState(_ int, rlm realm, clientId types.ClientId, height types.Height, consensusStateBytes []byte) bool

	// --- Connection ---
	NextConnectionId(_ int, rlm realm) types.ConnectionId
	SaveConnection(_ int, rlm realm, connectionId types.ConnectionId, connection types.Connection)
	GetConnection(connectionId types.ConnectionId) (types.Connection, bool)
}
