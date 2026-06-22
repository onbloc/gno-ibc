package core

import (
	"chain/params"
	"encoding/hex"

	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

var store *Store

func init() {
	store = newStore()
}

type Store struct {
	clientSeq  seqid.ID
	clientByID *bptree.BPTree // clientKey(ClientId) → *client

	connectionSeq        seqid.ID
	connectionClientByID *bptree.BPTree // connectionKey(ConnectionId) → ClientId

	channelSeq        seqid.ID
	channelClientByID *bptree.BPTree // channelKey(ChannelId) → ClientId

	membershipProofs    map[types.H256]types.H256
	nonMembershipProofs map[types.H256]types.H256

	ports map[string]app.IApp
}

type client struct {
	id                types.ClientId
	typ               types.ClientType
	creator           address
	lightClient       lightclient.Interface
	clientState       []byte
	consensusByHeight *bptree.BPTree // string(height.Bytes()) → []byte

	connectionsByID *bptree.BPTree // connectionKey(ConnectionId) → types.Connection
	channelsByID    *bptree.BPTree // channelKey(ChannelId) → *channelEntry

	batchPackets  map[types.H256]types.H256
	batchReceipts map[types.H256]types.H256
}

type channelEntry struct {
	channel  types.Channel
	portId   types.Bytes
	clientId types.ClientId // cached from connection at channel creation
}

func newStore() *Store {
	return &Store{
		clientByID:           bptree.NewBPTree32(),
		connectionClientByID: bptree.NewBPTree32(),
		channelClientByID:    bptree.NewBPTree32(),
		membershipProofs:     make(map[types.H256]types.H256),
		nonMembershipProofs:  make(map[types.H256]types.H256),
		ports:                make(map[string]app.IApp),
	}
}

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

// --- Key helpers ---

func clientKey(id types.ClientId) string {
	return seqid.ID(id).Binary()
}

func connectionKey(id types.ConnectionId) string {
	return seqid.ID(id).Binary()
}

func channelKey(id types.ChannelId) string {
	return seqid.ID(id).Binary()
}

func setChainParam(key string, value []byte) {
	// TODO find a way to assert this write in tests (difficult since params does
	// not expose getters)
	params.SetBytes(key, value)
}

// h256ChainParamKey encodes Union commitment paths for chain params. Unlike
// classic IBC string paths, Union paths are H256 storage keys and are mirrored
// into params as lowercase hex strings.
func h256ChainParamKey(key types.H256) string {
	return hex.EncodeToString(key[:])
}

// --- Client state ---

func (c *client) saveState(clientStateBytes []byte) {
	c.clientState = cloneBytes(clientStateBytes)
	setChainParam(h256ChainParamKey(types.ClientStatePath(c.id)), h256Bytes(keccak(clientStateBytes)))
}

func (c *client) saveConsensusState(height types.Height, consensusStateBytes []byte) {
	c.consensusByHeight.Set(string(height.Bytes()), cloneBytes(consensusStateBytes))
	setChainParam(h256ChainParamKey(types.ConsensusStatePath(c.id, height)), h256Bytes(keccak(consensusStateBytes)))
}

func (c *client) getConsensusState(height types.Height) ([]byte, bool) {
	v, found := c.consensusByHeight.Get(string(height.Bytes()))
	if !found {
		return nil, false
	}
	return cloneBytes(v.([]byte)), true
}

func (c *client) findConsensusState(height types.Height) ([]byte, bool) {
	v, found := c.consensusByHeight.Get(string(height.Bytes()))
	if !found {
		return nil, false
	}
	return cloneBytes(v.([]byte)), true
}

// --- Batch packets (per client) ---

func (c *client) saveBatchPackets(hash types.H256, value types.H256) {
	key := types.BatchPacketsPath(hash)
	c.batchPackets[key] = value
	setChainParam(h256ChainParamKey(key), value[:])
}

// setBatchPackets mirrors value in memory only (no chain-param write).
func (c *client) setBatchPackets(hash types.H256, value types.H256) {
	c.batchPackets[types.BatchPacketsPath(hash)] = value
}

func (c *client) getBatchPackets(hash types.H256) types.H256 {
	v, found := c.getBatchPacketsAtPath(types.BatchPacketsPath(hash))
	if !found {
		panic(ErrBatchPacketsNotFound)
	}
	return v
}

func (c *client) getBatchPacketsAtPath(path types.H256) (types.H256, bool) {
	v, found := c.batchPackets[path]
	if !found {
		var zero types.H256
		return zero, false
	}
	return v, true
}

func (c *client) deleteBatchPackets(hash types.H256) {
	var zero types.H256
	key := types.BatchPacketsPath(hash)
	delete(c.batchPackets, key)
	setChainParam(h256ChainParamKey(key), zero[:])
}

// --- Batch receipts (per client) ---

func (c *client) saveBatchReceipts(hash types.H256, value types.H256) {
	key := types.BatchReceiptsPath(hash)
	c.batchReceipts[key] = value
	setChainParam(h256ChainParamKey(key), value[:])
}

func (c *client) getBatchReceipts(hash types.H256) types.H256 {
	v, found := c.getBatchReceiptsAtPath(types.BatchReceiptsPath(hash))
	if !found {
		panic(ErrBatchReceiptsNotFound)
	}
	return v
}

func (c *client) getBatchReceiptsAtPath(path types.H256) (types.H256, bool) {
	v, found := c.batchReceipts[path]
	if !found {
		var zero types.H256
		return zero, false
	}
	return v, true
}

func (c *client) deleteBatchReceipts(hash types.H256) {
	var zero types.H256
	key := types.BatchReceiptsPath(hash)
	delete(c.batchReceipts, key)
	setChainParam(h256ChainParamKey(key), zero[:])
}

// --- Packet helpers (per client) ---

func (c *client) commitPacket(packet types.Packet) {
	c.saveBatchPackets(commitPacketHash(packet), types.COMMITMENT_MAGIC)
}

func (c *client) deletePacketCommitment(packet types.Packet) {
	var zero types.H256
	path := packetCommitmentPath(packet)
	delete(c.batchPackets, path)
	setChainParam(h256ChainParamKey(path), zero[:])
}

func (c *client) markPacketAcknowledged(packet types.Packet) error {
	path := packetCommitmentPath(packet)
	commitment, found := c.getBatchPacketsAtPath(path)
	if !found {
		return ErrPacketCommitmentNotFound
	}
	if commitment == types.COMMITMENT_MAGIC_ACK {
		return ErrPacketAlreadyAcknowledged
	}
	if commitment != types.COMMITMENT_MAGIC {
		return ErrPacketCommitmentNotFound
	}
	c.setBatchPackets(commitPacketHash(packet), types.COMMITMENT_MAGIC_ACK)
	return nil
}

func (c *client) hasPacketCommitment(packet types.Packet) bool {
	_, found := c.getBatchPacketsAtPath(packetCommitmentPath(packet))
	return found
}

func (c *client) commitAcknowledgement(packet types.Packet, ack []byte) {
	c.saveBatchReceipts(commitPacketHash(packet), types.CommitAcks([][]byte{ack}))
}

func (c *client) hasAcknowledgement(packet types.Packet) bool {
	v, ok := c.getBatchReceiptsAtPath(packetAcknowledgementPath(packet))
	return ok && v != types.COMMITMENT_MAGIC
}

func (c *client) acknowledgementHash(packet types.Packet) types.H256 {
	v, found := c.getBatchReceiptsAtPath(packetAcknowledgementPath(packet))
	if !found {
		var zero types.H256
		return zero
	}
	return v
}

func (c *client) setPacketReceipt(packet types.Packet) {
	c.saveBatchReceipts(commitPacketHash(packet), types.COMMITMENT_MAGIC)
}

func (c *client) hasPacketReceipt(packet types.Packet) bool {
	_, found := c.getBatchReceiptsAtPath(packetAcknowledgementPath(packet))
	return found
}

func (c *client) deletePacketReceipt(packet types.Packet) {
	var zero types.H256
	path := packetAcknowledgementPath(packet)
	delete(c.batchReceipts, path)
	setChainParam(h256ChainParamKey(path), zero[:])
}

// --- Committed proofs and timeout commitments (global paths) ---

func (s *Store) saveMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
	key := types.MembershipProofPath(clientId, proofHeight, path)
	s.membershipProofs[key] = value
	setChainParam(h256ChainParamKey(key), value[:])
}

func (s *Store) getMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte) (types.H256, bool) {
	v, found := s.membershipProofs[types.MembershipProofPath(clientId, proofHeight, path)]
	if !found {
		var zero types.H256
		return zero, false
	}
	return v, true
}

func (s *Store) saveNonMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
	key := types.NonMembershipProofPath(clientId, proofHeight, path)
	s.nonMembershipProofs[key] = value
	setChainParam(h256ChainParamKey(key), value[:])
}

func (s *Store) hasNonMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte) bool {
	v, found := s.nonMembershipProofs[types.NonMembershipProofPath(clientId, proofHeight, path)]
	return found && v == types.NON_MEMBERSHIP_COMMITMENT_VALUE
}

// --- ID sequences ---

func (s *Store) nextConnectionId() types.ConnectionId {
	return types.ConnectionId(uint32(s.connectionSeq.Next()))
}

func (s *Store) nextChannelId() types.ChannelId {
	return types.ChannelId(uint32(s.channelSeq.Next()))
}

// --- Client ---

func (s *Store) addClient(typ types.ClientType, creator address, lc lightclient.Interface) *client {
	clientId := types.ClientId(uint32(s.clientSeq.Next()))
	c := &client{
		id:                clientId,
		typ:               typ,
		creator:           creator,
		lightClient:       lc,
		consensusByHeight: bptree.NewBPTree32(),
		connectionsByID:   bptree.NewBPTree32(),
		channelsByID:      bptree.NewBPTree32(),
		batchPackets:      make(map[types.H256]types.H256),
		batchReceipts:     make(map[types.H256]types.H256),
	}
	s.clientByID.Set(clientKey(clientId), c)
	return c
}

func (s *Store) getClient(clientId types.ClientId) *client {
	v, found := s.clientByID.Get(clientKey(clientId))
	if !found {
		return nil
	}
	return v.(*client)
}

func (s *Store) lightClientOf(clientId types.ClientId) (lightclient.Interface, bool) {
	c := s.getClient(clientId)
	if c == nil {
		return nil, false
	}
	return c.lightClient, true
}

// --- App routing ---

func portKey(portId types.Bytes) string {
	return string(portId)
}

func (s *Store) getAppByPortId(portId types.Bytes) app.IApp {
	a, ok := s.ports[portKey(portId)]
	if !ok {
		panic("port " + string(portId) + " not found")
	}
	return a
}

// --- Connection ---

func (s *Store) saveConnection(connectionId types.ConnectionId, connection types.Connection) {
	c := s.getClient(connection.ClientId)
	if c == nil {
		panic("client " + connection.ClientId.String() + " not found")
	}
	c.connectionsByID.Set(connectionKey(connectionId), connection)
	s.connectionClientByID.Set(connectionKey(connectionId), connection.ClientId)
	setChainParam(h256ChainParamKey(types.ConnectionPath(connectionId)), h256Bytes(connectionValue(connection)))
}

func (s *Store) getConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	v, found := s.connectionClientByID.Get(connectionKey(connectionId))
	if !found {
		return types.Connection{}, false
	}
	c := s.getClient(v.(types.ClientId))
	if c == nil {
		return types.Connection{}, false
	}
	conn, found := c.connectionsByID.Get(connectionKey(connectionId))
	if !found {
		return types.Connection{}, false
	}
	return conn.(types.Connection), true
}

// --- Channel ---

func (s *Store) createChannel(channelId types.ChannelId, channel types.Channel, portId types.Bytes) {
	conn, ok := s.getConnection(channel.ConnectionId)
	if !ok {
		panic("connection " + channel.ConnectionId.String() + " not found")
	}
	entry := &channelEntry{
		channel:  channel,
		portId:   cloneBytes(portId),
		clientId: conn.ClientId,
	}
	c := s.getClient(conn.ClientId)
	if c == nil {
		panic("client " + conn.ClientId.String() + " not found")
	}
	c.channelsByID.Set(channelKey(channelId), entry)
	s.channelClientByID.Set(channelKey(channelId), conn.ClientId)
	setChainParam(h256ChainParamKey(types.ChannelPath(channelId)), h256Bytes(channelValue(channel)))
}

func (s *Store) saveChannel(channelId types.ChannelId, channel types.Channel) {
	entry, found := s.getChannelEntry(channelId)
	if !found {
		panic("channel " + channelId.String() + " not found")
	}
	entry.channel = channel
	setChainParam(h256ChainParamKey(types.ChannelPath(channelId)), h256Bytes(channelValue(channel)))
}

func (s *Store) getChannelEntry(channelId types.ChannelId) (*channelEntry, bool) {
	v, found := s.channelClientByID.Get(channelKey(channelId))
	if !found {
		return nil, false
	}
	c := s.getClient(v.(types.ClientId))
	if c == nil {
		return nil, false
	}
	entry, found := c.channelsByID.Get(channelKey(channelId))
	if !found {
		return nil, false
	}
	return entry.(*channelEntry), true
}

func (s *Store) getChannel(channelId types.ChannelId) types.Channel {
	entry, found := s.getChannelEntry(channelId)
	if !found {
		panic("channel " + channelId.String() + " not found")
	}
	return entry.channel
}

func (s *Store) getChannelOwner(channelId types.ChannelId) types.Bytes {
	entry, found := s.getChannelEntry(channelId)
	if !found {
		panic("channel " + channelId.String() + " not found")
	}
	return entry.portId
}

// clientForChannel returns the client associated with channelId via the cached
// clientId in the channel entry. Panics if the channel or client is not found.
func (s *Store) clientForChannel(channelId types.ChannelId) *client {
	entry, found := s.getChannelEntry(channelId)
	if !found {
		panic("channel " + channelId.String() + " not found")
	}
	c := s.getClient(entry.clientId)
	if c == nil {
		panic("client " + entry.clientId.String() + " not found")
	}
	return c
}

// --- Store-level packet delegation (routes via channel ID) ---
// These allow packet.gno and tests to call store.* without holding a *client.
// All safe variants (has*/acknowledgementHash) return zero/false when the channel
// or client is not found instead of panicking.

func (s *Store) commitPacket(packet types.Packet) {
	s.clientForChannel(packet.SourceChannelId).commitPacket(packet)
}

func (s *Store) deletePacketCommitment(packet types.Packet) {
	s.clientForChannel(packet.SourceChannelId).deletePacketCommitment(packet)
}

func (s *Store) hasPacketCommitment(packet types.Packet) bool {
	entry, ok := s.getChannelEntry(packet.SourceChannelId)
	if !ok {
		return false
	}
	c := s.getClient(entry.clientId)
	if c == nil {
		return false
	}
	return c.hasPacketCommitment(packet)
}

func (s *Store) commitAcknowledgement(packet types.Packet, ack []byte) {
	s.clientForChannel(packet.DestinationChannelId).commitAcknowledgement(packet, ack)
}

func (s *Store) hasAcknowledgement(packet types.Packet) bool {
	entry, ok := s.getChannelEntry(packet.DestinationChannelId)
	if !ok {
		return false
	}
	c := s.getClient(entry.clientId)
	if c == nil {
		return false
	}
	return c.hasAcknowledgement(packet)
}

func (s *Store) acknowledgementHash(packet types.Packet) types.H256 {
	entry, ok := s.getChannelEntry(packet.DestinationChannelId)
	if !ok {
		var zero types.H256
		return zero
	}
	c := s.getClient(entry.clientId)
	if c == nil {
		var zero types.H256
		return zero
	}
	return c.acknowledgementHash(packet)
}

func (s *Store) setPacketReceipt(packet types.Packet) {
	s.clientForChannel(packet.DestinationChannelId).setPacketReceipt(packet)
}

func (s *Store) hasPacketReceipt(packet types.Packet) bool {
	entry, ok := s.getChannelEntry(packet.DestinationChannelId)
	if !ok {
		return false
	}
	c := s.getClient(entry.clientId)
	if c == nil {
		return false
	}
	return c.hasPacketReceipt(packet)
}

func (s *Store) deletePacketReceipt(packet types.Packet) {
	s.clientForChannel(packet.DestinationChannelId).deletePacketReceipt(packet)
}
