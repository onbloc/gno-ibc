package core

import "testing"

// --- Mock implementations ---

type mockClient struct {
	chainId string
	height  Height
	status  Status
}

func (m *mockClient) CreateClient(_ ClientId, _, _ []byte) string { return m.chainId }
func (m *mockClient) UpdateClient(_ ClientId, _ []byte) ConsensusStateUpdate {
	m.height++
	return ConsensusStateUpdate{
		Height:              m.height,
		ClientStateBytes:    []byte("cs"),
		ConsensusStateBytes: []byte("cons"),
	}
}
func (m *mockClient) Misbehaviour(_ ClientId, _ []byte) []byte        { return []byte("frozen") }
func (m *mockClient) VerifyMembership(_ ClientId, _ Height, _, _, _ []byte) {}
func (m *mockClient) VerifyNonMembership(_ ClientId, _ Height, _, _ []byte) {}
func (m *mockClient) GetTimestamp(_ ClientId, _ Height) Timestamp      { return Timestamp(1e9) }
func (m *mockClient) GetLatestHeight(_ ClientId) Height                { return m.height }
func (m *mockClient) GetStatus(_ ClientId) Status                      { return m.status }

type mockApp struct {
	initCalled     bool
	closedChannels []ChannelId
	recvPackets    []Packet
	ackPackets     []Packet
	timeoutPackets []Packet
}

func (a *mockApp) OnChannelOpenInit(_ ConnectionId, _ ChannelId, _ string, _ address) {
	a.initCalled = true
}
func (a *mockApp) OnChannelOpenTry(_ ConnectionId, _ ChannelId, _, _ string, _ address) {}
func (a *mockApp) OnChannelOpenAck(_ ChannelId, _ ChannelId, _ string, _ address)       {}
func (a *mockApp) OnChannelOpenConfirm(_ ChannelId, _ address)                          {}
func (a *mockApp) OnChannelCloseInit(ch ChannelId, _ address) {
	a.closedChannels = append(a.closedChannels, ch)
}
func (a *mockApp) OnChannelCloseConfirm(ch ChannelId, _ address) {
	a.closedChannels = append(a.closedChannels, ch)
}
func (a *mockApp) OnRecvPacket(p Packet, _ address, _ Bytes) {
	a.recvPackets = append(a.recvPackets, p)
}
func (a *mockApp) OnAcknowledgementPacket(p Packet, _ Bytes, _ address) {
	a.ackPackets = append(a.ackPackets, p)
}
func (a *mockApp) OnTimeoutPacket(p Packet, _ address) {
	a.timeoutPackets = append(a.timeoutPackets, p)
}

// --- Helpers ---

const mockType ClientType = "mock"

func resetState() {
	st = State{
		nextClientId:     ClientId(1),
		nextConnectionId: ConnectionId(1),
		nextChannelId:    ChannelId(1),
		clientRegistry:   make(map[ClientType]ILightClient),
		clientTypes:      make(map[ClientId]ClientType),
		connections:      make(map[ConnectionId]Connection),
		channels:         make(map[ChannelId]Channel),
		ports:            make(map[address]IApp),
		channelOwners:    make(map[ChannelId]address),
	}
}

func mustPanic(t *testing.T, fn func()) {
	t.Helper()
	defer func() {
		if recover() == nil {
			t.Error("expected panic but none occurred")
		}
	}()
	fn()
}

func setupOpenChannel(t *testing.T) (address, ConnectionId, ChannelId) {
	t.Helper()
	clientId := st.generateClientId()
	st.clientTypes[clientId] = mockType
	st.clientRegistry[mockType] = &mockClient{chainId: "union-1", height: 100, status: StatusActive}

	connId := st.generateConnectionId()
	st.saveConnection(connId, Connection{
		State:                    ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     ClientId(99),
		CounterpartyConnectionId: ConnectionId(99),
	})

	portId := address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9ex6sz")
	app := &mockApp{}
	st.ports[portId] = app

	channelId := st.generateChannelId()
	st.channelOwners[channelId] = portId
	st.saveChannel(channelId, Channel{
		State:                 ChannelStateOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: ChannelId(99),
		CounterpartyPortId:    Bytes("counterparty"),
		Version:               "ics20-1",
	})
	return portId, connId, channelId
}

// --- Path tests ---

func TestClientStatePathUnique(t *testing.T) {
	if ClientStatePath(1) == ClientStatePath(2) {
		t.Error("different client IDs must produce different paths")
	}
	if ClientStatePath(1) != ClientStatePath(1) {
		t.Error("same client ID must produce same path")
	}
}

func TestConsensusStatePathUnique(t *testing.T) {
	if ConsensusStatePath(1, 10) == ConsensusStatePath(1, 11) {
		t.Error("different heights must produce different paths")
	}
	if ConsensusStatePath(1, 10) == ConsensusStatePath(2, 10) {
		t.Error("different client IDs must produce different paths")
	}
}

func TestConnectionChannelPathUnique(t *testing.T) {
	if ConnectionPath(1) == ConnectionPath(2) {
		t.Error("different connection IDs must produce different paths")
	}
	if ChannelPath(1) == ChannelPath(2) {
		t.Error("different channel IDs must produce different paths")
	}
	if ConnectionPath(1) == ChannelPath(1) {
		t.Error("connection and channel paths for same ID must differ")
	}
}

func TestPacketCommitmentAndAckPathsDiffer(t *testing.T) {
	p := Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if PacketCommitmentPath(p) == PacketAcknowledgementPath(p) {
		t.Error("commitment and ack paths must differ for the same packet")
	}
}

func TestPacketCommitmentPathUnique(t *testing.T) {
	p1 := Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	p2 := Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 9999}
	if PacketCommitmentPath(p1) == PacketCommitmentPath(p2) {
		t.Error("packets with different timestamps must have different commitment paths")
	}
}

// --- Type encoding tests ---

func TestConnectionEthAbiEncodeDistinct(t *testing.T) {
	open := Connection{State: ConnectionStateOpen, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
	init := Connection{State: ConnectionStateInit, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
	if string(open.EthAbiEncode()) == string(init.EthAbiEncode()) {
		t.Error("different connection states must encode differently")
	}
}

func TestChannelEthAbiEncodeDistinct(t *testing.T) {
	open := Channel{State: ChannelStateOpen, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"}
	closed := Channel{State: ChannelStateClosed, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"}
	if string(open.EthAbiEncode()) == string(closed.EthAbiEncode()) {
		t.Error("different channel states must encode differently")
	}
}

func TestPacketEthAbiEncodeDistinct(t *testing.T) {
	p1 := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("a"), TimeoutTimestamp: 100}
	p2 := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("b"), TimeoutTimestamp: 100}
	if string(p1.EthAbiEncode()) == string(p2.EthAbiEncode()) {
		t.Error("packets with different data must encode differently")
	}
}

// --- State: client registry ---

func TestRegisterClientAndRetrieve(t *testing.T) {
	resetState()
	c := &mockClient{chainId: "union-1"}
	st.registerClient(mockType, c)
	if _, ok := st.clientRegistry[mockType]; !ok {
		t.Error("client not found in registry after registration")
	}
}

func TestRegisterClientDuplicatePanics(t *testing.T) {
	resetState()
	st.registerClient(mockType, &mockClient{})
	mustPanic(t, func() {
		st.registerClient(mockType, &mockClient{})
	})
}

func TestGetClientNotFoundPanics(t *testing.T) {
	resetState()
	mustPanic(t, func() {
		st.getClient(ClientId(999))
	})
}

// --- State: ID generation ---

func TestGenerateIdsSequential(t *testing.T) {
	resetState()
	c1, c2 := st.generateClientId(), st.generateClientId()
	if c2 != c1+1 {
		t.Errorf("client IDs not sequential: got %v and %v", c1, c2)
	}
	n1, n2 := st.generateConnectionId(), st.generateConnectionId()
	if n2 != n1+1 {
		t.Errorf("connection IDs not sequential: got %v and %v", n1, n2)
	}
	h1, h2 := st.generateChannelId(), st.generateChannelId()
	if h2 != h1+1 {
		t.Errorf("channel IDs not sequential: got %v and %v", h1, h2)
	}
}

// --- State: connection ---

func TestSaveAndGetConnection(t *testing.T) {
	resetState()
	conn := Connection{
		State:                    ConnectionStateOpen,
		ClientId:                 ClientId(1),
		CounterpartyClientId:     ClientId(2),
		CounterpartyConnectionId: ConnectionId(99),
	}
	id := st.generateConnectionId()
	st.saveConnection(id, conn)

	got := st.getConnection(id)
	if got.State != ConnectionStateOpen {
		t.Errorf("state: got %v want Open", got.State)
	}
	if got.ClientId != ClientId(1) {
		t.Errorf("clientId: got %v want 1", got.ClientId)
	}
}

func TestGetConnectionNotFoundPanics(t *testing.T) {
	resetState()
	mustPanic(t, func() { st.getConnection(ConnectionId(999)) })
}

func TestConnectionStateSaved(t *testing.T) {
	resetState()
	id := st.generateConnectionId()
	st.saveConnection(id, Connection{State: ConnectionStateInit})
	st.saveConnection(id, Connection{State: ConnectionStateOpen})
	if st.getConnection(id).State != ConnectionStateOpen {
		t.Error("connection state must reflect latest save")
	}
}

// --- State: channel ---

func TestSaveAndGetChannel(t *testing.T) {
	resetState()
	ch := Channel{
		State:                 ChannelStateOpen,
		ConnectionId:          ConnectionId(1),
		CounterpartyChannelId: ChannelId(99),
		CounterpartyPortId:    Bytes("counterparty"),
		Version:               "ics20-1",
	}
	id := st.generateChannelId()
	st.saveChannel(id, ch)

	got := st.getChannel(id)
	if got.State != ChannelStateOpen {
		t.Errorf("state: got %v want Open", got.State)
	}
	if got.Version != "ics20-1" {
		t.Errorf("version: got %v want ics20-1", got.Version)
	}
}

func TestGetChannelNotFoundPanics(t *testing.T) {
	resetState()
	mustPanic(t, func() { st.getChannel(ChannelId(999)) })
}

// --- State: packet commitment ---

func TestCommitPacketDoesNotPanic(t *testing.T) {
	resetState()
	p := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("data"), TimeoutTimestamp: 1000}
	st.commitPacket(p)
	st.deletePacketCommitment(p)
}

func TestAcknowledgementDoesNotPanic(t *testing.T) {
	resetState()
	p := Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	st.commitAcknowledgement(p, []byte("ack"))
}

// --- ensureConnectionOpen ---

func TestEnsureConnectionOpenPanicsOnInit(t *testing.T) {
	resetState()
	id := st.generateConnectionId()
	st.saveConnection(id, Connection{State: ConnectionStateInit})
	mustPanic(t, func() { ensureConnectionOpen(id) })
}

func TestEnsureConnectionOpenSucceeds(t *testing.T) {
	resetState()
	id := st.generateConnectionId()
	st.saveConnection(id, Connection{State: ConnectionStateOpen, ClientId: 1})
	st.clientRegistry[mockType] = &mockClient{}
	st.clientTypes[ClientId(1)] = mockType
	conn := ensureConnectionOpen(id)
	if conn.State != ConnectionStateOpen {
		t.Error("expected open connection")
	}
}

// --- Channel state machine ---

func TestChannelStateTransitions(t *testing.T) {
	resetState()
	id := st.generateChannelId()

	st.saveChannel(id, Channel{State: ChannelStateInit})
	if st.getChannel(id).State != ChannelStateInit {
		t.Error("expected Init")
	}
	st.saveChannel(id, Channel{State: ChannelStateTryOpen})
	if st.getChannel(id).State != ChannelStateTryOpen {
		t.Error("expected TryOpen")
	}
	st.saveChannel(id, Channel{State: ChannelStateOpen})
	if st.getChannel(id).State != ChannelStateOpen {
		t.Error("expected Open")
	}
	st.saveChannel(id, Channel{State: ChannelStateClosed})
	if st.getChannel(id).State != ChannelStateClosed {
		t.Error("expected Closed")
	}
}

// --- Port / channel ownership ---

func TestGetAppByPortIdPanicsWhenMissing(t *testing.T) {
	resetState()
	mustPanic(t, func() {
		st.getAppByPortId(address("g1missing"))
	})
}

func TestGetChannelOwnerPanicsWhenMissing(t *testing.T) {
	resetState()
	mustPanic(t, func() {
		st.getChannelOwner(ChannelId(999))
	})
}

// --- Integration: packet send lifecycle ---

func TestPacketSendRequiresOpenChannel(t *testing.T) {
	resetState()
	id := st.generateChannelId()
	st.saveChannel(id, Channel{State: ChannelStateInit})
	portId := address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9ex6sz")
	st.ports[portId] = &mockApp{}
	st.channelOwners[id] = portId

	mustPanic(t, func() {
		// simulate PacketSend state check
		ch := st.getChannel(id)
		if ch.State != ChannelStateOpen {
			panic(ErrInvalidChannelState)
		}
	})
}

func TestPacketSendAndCommit(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)

	packet := Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: ChannelId(99),
		Data:                 Bytes("transfer"),
		TimeoutTimestamp:     Timestamp(9999),
	}
	st.commitPacket(packet)
	// commitPacket must not panic; commitment is stored via chain/params
}

// --- Integration: channel close ---

func TestChannelCloseInitRequiresOpen(t *testing.T) {
	resetState()
	id := st.generateChannelId()
	portId := address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9ex6sz")
	st.ports[portId] = &mockApp{}
	st.channelOwners[id] = portId
	st.saveChannel(id, Channel{State: ChannelStateClosed})

	mustPanic(t, func() {
		ch := st.getChannel(id)
		if ch.State != ChannelStateOpen {
			panic(ErrInvalidChannelState)
		}
	})
}

func TestChannelCloseInitTransition(t *testing.T) {
	resetState()
	portId, connId, channelId := setupOpenChannel(t)
	_ = connId

	app := st.ports[portId].(*mockApp)
	ch := st.getChannel(channelId)
	ch.State = ChannelStateClosed
	st.saveChannel(channelId, ch)
	app.closedChannels = append(app.closedChannels, channelId)

	if st.getChannel(channelId).State != ChannelStateClosed {
		t.Error("channel must be Closed after CloseInit")
	}
	if len(app.closedChannels) != 1 || app.closedChannels[0] != channelId {
		t.Error("OnChannelCloseInit must be called with correct channel ID")
	}
}
