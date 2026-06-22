package core

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// store_istore.gno adapts the proxy-private Store to the IStore interface the
// impl is injected with. Each method routes to the existing client operations,
// keeping the nested *client structure and the chain-param commitment mirror
// private to the proxy. Setters take the borrow-rule (_ int, rlm realm, ...)
// form; the realm token is threaded by the caller and unused here because the
// underlying writes already run in the proxy's ownership context.
var _ IStore = (*Store)(nil)

// AddClient allocates a new client for the light client object and returns its id.
func (s *Store) AddClient(_ int, rlm realm, typ types.ClientType, creator address, lc lightclient.Interface) types.ClientId {
	return s.addClient(typ, creator, lc).id
}

// ClientExists reports whether a client is registered under clientId.
func (s *Store) ClientExists(clientId types.ClientId) bool {
	return s.getClient(clientId) != nil
}

// ClientType returns the registered client type for clientId.
func (s *Store) ClientType(clientId types.ClientId) (types.ClientType, bool) {
	c := s.getClient(clientId)
	if c == nil {
		return "", false
	}
	return c.typ, true
}

// GetLightClient returns the stored light client object for clientId.
func (s *Store) GetLightClient(clientId types.ClientId) (lightclient.Interface, bool) {
	return s.lightClientOf(clientId)
}

// SetLightClient replaces a client's light client object (force-update recovery),
// returning false when the client is unknown.
func (s *Store) SetLightClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) bool {
	c := s.getClient(clientId)
	if c == nil {
		return false
	}
	c.lightClient = lc
	return true
}

// SaveClientState mirrors the client state bytes for queries and counterparty
// proofs, returning false when the client is unknown.
func (s *Store) SaveClientState(_ int, rlm realm, clientId types.ClientId, clientStateBytes []byte) bool {
	c := s.getClient(clientId)
	if c == nil {
		return false
	}
	c.saveState(clientStateBytes)
	return true
}

// SaveConsensusState records the consensus state at height, returning false when
// the client is unknown.
func (s *Store) SaveConsensusState(_ int, rlm realm, clientId types.ClientId, height types.Height, consensusStateBytes []byte) bool {
	c := s.getClient(clientId)
	if c == nil {
		return false
	}
	c.saveConsensusState(height, consensusStateBytes)
	return true
}

// NextConnectionId allocates the next connection id from the sequence.
func (s *Store) NextConnectionId(_ int, rlm realm) types.ConnectionId {
	return s.nextConnectionId()
}

// SaveConnection persists a connection and mirrors its commitment.
func (s *Store) SaveConnection(_ int, rlm realm, connectionId types.ConnectionId, connection types.Connection) {
	s.saveConnection(connectionId, connection)
}

// GetConnection returns the stored connection for connectionId.
func (s *Store) GetConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	return s.getConnection(connectionId)
}

// NextChannelId allocates the next channel id from the sequence.
func (s *Store) NextChannelId(_ int, rlm realm) types.ChannelId {
	return s.nextChannelId()
}

// CreateChannel persists a new channel owned by portId and mirrors its commitment.
func (s *Store) CreateChannel(_ int, rlm realm, channelId types.ChannelId, channel types.Channel, portId types.Bytes) {
	s.createChannel(channelId, channel, portId)
}

// SaveChannel updates a stored channel and mirrors its commitment.
func (s *Store) SaveChannel(_ int, rlm realm, channelId types.ChannelId, channel types.Channel) {
	s.saveChannel(channelId, channel)
}

// GetChannel returns the stored channel for channelId.
func (s *Store) GetChannel(channelId types.ChannelId) (types.Channel, bool) {
	entry, ok := s.getChannelEntry(channelId)
	if !ok {
		return types.Channel{}, false
	}
	return entry.channel, true
}

// GetChannelOwner returns the port id that owns channelId.
func (s *Store) GetChannelOwner(channelId types.ChannelId) (types.Bytes, bool) {
	entry, ok := s.getChannelEntry(channelId)
	if !ok {
		return nil, false
	}
	return entry.portId, true
}

// GetAppByPortId returns the IBC app registered at portId.
func (s *Store) GetAppByPortId(portId types.Bytes) (app.IApp, bool) {
	a, ok := s.ports[portKey(portId)]
	return a, ok
}

// HasApp reports whether an app is registered at portId.
func (s *Store) HasApp(portId types.Bytes) bool {
	_, ok := s.ports[portKey(portId)]
	return ok
}

// RegisterAppAtPort installs an app at portId, panicking if one is already
// registered there.
func (s *Store) RegisterAppAtPort(_ int, rlm realm, portId types.Bytes, a app.IApp) {
	registerAppAtPort([]byte(portId), a)
}

// HasPacketCommitment reports whether the source-side packet commitment exists.
func (s *Store) HasPacketCommitment(packet types.Packet) bool {
	return s.hasPacketCommitment(packet)
}

// CommitPacket records the source-side commitment for a sent packet.
func (s *Store) CommitPacket(_ int, rlm realm, packet types.Packet) {
	s.commitPacket(packet)
}

// MarkPacketAcknowledged flips a source-side commitment to acknowledged.
func (s *Store) MarkPacketAcknowledged(_ int, rlm realm, packet types.Packet) error {
	return s.clientForChannel(packet.SourceChannelId).markPacketAcknowledged(packet)
}

// HasPacketReceipt reports whether a destination-side receipt exists.
func (s *Store) HasPacketReceipt(packet types.Packet) bool {
	return s.hasPacketReceipt(packet)
}

// SetPacketReceipt records a destination-side receipt (replay protection).
func (s *Store) SetPacketReceipt(_ int, rlm realm, packet types.Packet) {
	s.setPacketReceipt(packet)
}

// CommitAcknowledgement records the acknowledgement for a received packet.
func (s *Store) CommitAcknowledgement(_ int, rlm realm, packet types.Packet, ack []byte) {
	s.commitAcknowledgement(packet, ack)
}

// AcknowledgementReceipt returns the receipt stored at a packet's ack path.
func (s *Store) AcknowledgementReceipt(channelId types.ChannelId, packet types.Packet) (types.H256, bool) {
	return s.clientForChannel(channelId).getBatchReceiptsAtPath(packetAcknowledgementPath(packet))
}

// PacketCommitment returns the commitment stored at a packet's commitment path.
func (s *Store) PacketCommitment(channelId types.ChannelId, packet types.Packet) (types.H256, bool) {
	return s.clientForChannel(channelId).getBatchPacketsAtPath(packetCommitmentPath(packet))
}

// SaveBatchPackets records a batch commitment under batchHash.
func (s *Store) SaveBatchPackets(_ int, rlm realm, channelId types.ChannelId, batchHash, value types.H256) {
	s.clientForChannel(channelId).saveBatchPackets(batchHash, value)
}

// SaveBatchReceipts records a batch receipt under batchHash.
func (s *Store) SaveBatchReceipts(_ int, rlm realm, channelId types.ChannelId, batchHash, value types.H256) {
	s.clientForChannel(channelId).saveBatchReceipts(batchHash, value)
}

// SaveMembershipProof records a verified membership commitment.
func (s *Store) SaveMembershipProof(_ int, rlm realm, clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
	s.saveMembershipProof(clientId, proofHeight, path, value)
}

// SaveNonMembershipProof records a verified non-membership commitment.
func (s *Store) SaveNonMembershipProof(_ int, rlm realm, clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
	s.saveNonMembershipProof(clientId, proofHeight, path, value)
}
