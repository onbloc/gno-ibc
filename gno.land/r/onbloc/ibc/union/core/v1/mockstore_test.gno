package impl

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// mockStore is an in-memory core.IStore for the unit tests. The production store
// lives in the proxy realm, so its borrow-rule setters can only be driven from
// that realm; a test in this realm cannot mutate it without tripping the
// readonly-object guard. This mock is backed by plain maps owned by the test
// realm, so the injected impl can read and write it directly.
type mockClient struct {
	typ         types.ClientType
	creator     address
	impl        lightclient.ClientImpl
	lc          lightclient.Interface
	clientState []byte
	consensus   map[string][]byte // height.String() -> consensus bytes
	clientStore map[string][]byte // light client storage writes
}

type mockStore struct {
	seq      uint32
	registry map[string]lightclient.ClientImpl
	clients  map[uint32]*mockClient
	connSeq uint32
	connections   map[uint32]types.Connection
	chanSeq       uint32
	channels      map[uint32]types.Channel
	channelOwners map[uint32]types.Bytes
	ports         map[string]app.IApp
	commitments   map[string]types.H256 // per-packet source commitment
	receipts      map[string]types.H256 // per-packet destination receipt / ack
	batchPackets  map[string]types.H256
	batchReceipts map[string]types.H256
}

var _ core.IStore = (*mockStore)(nil)

func newMockStore() *mockStore {
	return &mockStore{
		registry:    map[string]lightclient.ClientImpl{},
		clients:     map[uint32]*mockClient{},
		connections: map[uint32]types.Connection{},
		channels:      map[uint32]types.Channel{},
		channelOwners: map[uint32]types.Bytes{},
		ports:         map[string]app.IApp{},
		commitments:   map[string]types.H256{},
		receipts:      map[string]types.H256{},
		batchPackets:  map[string]types.H256{},
		batchReceipts: map[string]types.H256{},
	}
}

// packetKey is a deterministic per-packet key mirroring the store's per-packet
// commitment/receipt paths (which are derived from the packet hash).
func packetKey(packet types.Packet) string {
	return packet.SourceChannelId.String() + "|" +
		packet.DestinationChannelId.String() + "|" +
		string(packet.Data) + "|" +
		packet.TimeoutTimestamp.String()
}

func (m *mockStore) HasPacketCommitment(packet types.Packet) bool {
	_, ok := m.commitments[packetKey(packet)]
	return ok
}

func (m *mockStore) CommitPacket(_ int, rlm realm, packet types.Packet) {
	m.commitments[packetKey(packet)] = types.COMMITMENT_MAGIC
}

func (m *mockStore) SetPacketAcknowledged(_ int, rlm realm, packet types.Packet) {
	m.commitments[packetKey(packet)] = types.COMMITMENT_MAGIC_ACK
}

func (m *mockStore) HasPacketReceipt(packet types.Packet) bool {
	_, ok := m.receipts[packetKey(packet)]
	return ok
}

func (m *mockStore) SetPacketReceipt(_ int, rlm realm, packet types.Packet) {
	m.receipts[packetKey(packet)] = types.COMMITMENT_MAGIC
}

func (m *mockStore) CommitAcknowledgement(_ int, rlm realm, packet types.Packet, ack []byte) {
	m.receipts[packetKey(packet)] = types.CommitAcks([][]byte{ack})
}

func (m *mockStore) AcknowledgementReceipt(channelId types.ChannelId, packet types.Packet) (types.H256, bool) {
	v, ok := m.receipts[packetKey(packet)]
	return v, ok
}

func (m *mockStore) PacketCommitment(channelId types.ChannelId, packet types.Packet) (types.H256, bool) {
	v, ok := m.commitments[packetKey(packet)]
	return v, ok
}

func (m *mockStore) SaveBatchPackets(_ int, rlm realm, channelId types.ChannelId, batchHash, value types.H256) {
	m.batchPackets[string(batchHash[:])] = value
}

func (m *mockStore) SaveBatchReceipts(_ int, rlm realm, channelId types.ChannelId, batchHash, value types.H256) {
	m.batchReceipts[string(batchHash[:])] = value
}

func (m *mockStore) SaveMembershipProof(_ int, rlm realm, clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
}

func (m *mockStore) SaveNonMembershipProof(_ int, rlm realm, clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
}

func (m *mockStore) ClientStateBytes(clientId types.ClientId) ([]byte, bool) {
	c, ok := m.clients[uint32(clientId)]
	if !ok || len(c.clientState) == 0 {
		return nil, false
	}
	return c.clientState, true
}

func (m *mockStore) ConsensusStateBytes(clientId types.ClientId, height types.Height) ([]byte, bool) {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return nil, false
	}
	v, ok := c.consensus[height.String()]
	return v, ok
}

func (m *mockStore) BatchPacketsAt(batchHash types.H256) (types.H256, bool) {
	v, ok := m.batchPackets[string(batchHash[:])]
	return v, ok
}

func (m *mockStore) BatchReceiptsAt(batchHash types.H256) (types.H256, bool) {
	v, ok := m.batchReceipts[string(batchHash[:])]
	return v, ok
}

// registerApp is a test helper that installs an app at a port id.
func (m *mockStore) registerApp(portId types.Bytes, a app.IApp) {
	m.ports[string(portId)] = a
}

// newTestImpl builds a v1 impl bound to a fresh mock store, the way the proxy
// injects its real store at install time.
func newTestImpl() *coreV1 {
	return &coreV1{store: newMockStore()}
}

func (m *mockStore) RegisterClient(_ int, rlm realm, typ types.ClientType, impl lightclient.ClientImpl) {
	key := typ.String()
	if _, ok := m.registry[key]; ok {
		panic("client type already exists")
	}
	m.registry[key] = impl
}

func (m *mockStore) ClientRegistry(typ types.ClientType) (lightclient.ClientImpl, bool) {
	impl, found := m.registry[string(typ)]
	return impl, found
}

func (m *mockStore) HasRegisteredClient(typ types.ClientType) bool {
	_, found := m.registry[string(typ)]
	return found
}

func (m *mockStore) AddClient(_ int, rlm realm, typ types.ClientType, creator address, lc lightclient.Interface) types.ClientId {
	m.seq++
	id := m.seq
	impl := m.registry[string(typ)]
	m.clients[id] = &mockClient{typ: typ, creator: creator, impl: impl, lc: lc, consensus: map[string][]byte{}, clientStore: map[string][]byte{}}
	return types.ClientId(id)
}

func (m *mockStore) GetClientImpl(clientId types.ClientId) (lightclient.ClientImpl, bool) {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return nil, false
	}
	return c.impl, true
}

func (m *mockStore) SaveClientStore(_ int, rlm realm, clientId types.ClientId, key string, value []byte) bool {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return false
	}
	c.clientStore[key] = value
	return true
}

func (m *mockStore) ClientExists(clientId types.ClientId) bool {
	_, ok := m.clients[uint32(clientId)]
	return ok
}

func (m *mockStore) ClientType(clientId types.ClientId) (types.ClientType, bool) {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return "", false
	}
	return c.typ, true
}

func (m *mockStore) GetLightClient(clientId types.ClientId) (lightclient.Interface, bool) {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return nil, false
	}
	return c.lc, true
}

func (m *mockStore) SetLightClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) bool {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return false
	}
	c.lc = lc
	return true
}

func (m *mockStore) SaveClientState(_ int, rlm realm, clientId types.ClientId, clientStateBytes []byte) bool {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return false
	}
	c.clientState = clientStateBytes
	return true
}

func (m *mockStore) SaveConsensusState(_ int, rlm realm, clientId types.ClientId, height types.Height, consensusStateBytes []byte) bool {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return false
	}
	c.consensus[height.String()] = consensusStateBytes
	return true
}

func (m *mockStore) NextConnectionId(_ int, rlm realm) types.ConnectionId {
	m.connSeq++
	return types.ConnectionId(m.connSeq)
}

func (m *mockStore) SaveConnection(_ int, rlm realm, connectionId types.ConnectionId, connection types.Connection) {
	m.connections[uint32(connectionId)] = connection
}

func (m *mockStore) GetConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	conn, ok := m.connections[uint32(connectionId)]
	return conn, ok
}

func (m *mockStore) NextChannelId(_ int, rlm realm) types.ChannelId {
	m.chanSeq++
	return types.ChannelId(m.chanSeq)
}

// currentChannelId returns the most recently allocated channel id, letting tests
// recover the id that ChannelOpen* no longer returns.
func (m *mockStore) currentChannelId() types.ChannelId {
	return types.ChannelId(m.chanSeq)
}

func (m *mockStore) CreateChannel(_ int, rlm realm, channelId types.ChannelId, channel types.Channel, portId types.Bytes) {
	m.channels[uint32(channelId)] = channel
	m.channelOwners[uint32(channelId)] = portId
}

func (m *mockStore) SaveChannel(_ int, rlm realm, channelId types.ChannelId, channel types.Channel) {
	m.channels[uint32(channelId)] = channel
}

func (m *mockStore) GetChannel(channelId types.ChannelId) (types.Channel, bool) {
	ch, ok := m.channels[uint32(channelId)]
	return ch, ok
}

func (m *mockStore) GetChannels() ([]types.Channel, error) {
	out := make([]types.Channel, 0, len(m.channels))
	for _, ch := range m.channels {
		out = append(out, ch)
	}
	return out, nil
}

func (m *mockStore) GetChannelOwner(channelId types.ChannelId) (types.Bytes, bool) {
	p, ok := m.channelOwners[uint32(channelId)]
	return p, ok
}

func (m *mockStore) GetAppByPortId(portId types.Bytes) (app.IApp, bool) {
	a, ok := m.ports[string(portId)]
	return a, ok
}

func (m *mockStore) HasApp(portId types.Bytes) bool {
	_, ok := m.ports[string(portId)]
	return ok
}

func (m *mockStore) RegisterAppAtPort(_ int, rlm realm, portId types.Bytes, a app.IApp) {
	if _, ok := m.ports[string(portId)]; ok {
		panic("port already registered")
	}
	m.ports[string(portId)] = a
}
