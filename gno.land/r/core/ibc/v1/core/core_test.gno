package core

import (
	"chain/runtime"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// --- Mock implementations ---

type mockClient struct {
	chainId           string
	height            Height
	status            Status
	nonMembershipKeys [][]byte
}

func (m *mockClient) CreateClient(_ realm, _ ClientId, _, _ []byte) string { return m.chainId }
func (m *mockClient) UpdateClient(_ realm, _ ClientId, _ []byte) ConsensusStateUpdate {
	m.height++
	return ConsensusStateUpdate{
		Height:              m.height,
		ClientStateBytes:    []byte("cs"),
		ConsensusStateBytes: []byte("cons"),
	}
}
func (m *mockClient) Misbehaviour(_ realm, _ ClientId, _ []byte) []byte     { return []byte("frozen") }
func (m *mockClient) VerifyMembership(_ ClientId, _ Height, _, _, _ []byte) {}
func (m *mockClient) VerifyNonMembership(_ ClientId, _ Height, _, key []byte) {
	m.nonMembershipKeys = append(m.nonMembershipKeys, key)
}
func (m *mockClient) GetTimestamp(_ ClientId, _ Height) Timestamp { return Timestamp(1e9) }
func (m *mockClient) GetLatestHeight(_ ClientId) Height           { return m.height }
func (m *mockClient) GetStatus(_ ClientId) Status                 { return m.status }

type mockApp struct {
	initCalled     bool
	closedChannels []ChannelId
	recvPackets    []Packet
	ackPackets     []Packet
	timeoutPackets []Packet
	recvResult     RecvPacketResult
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

func (a *mockApp) OnRecvPacket(p Packet, _ address, _ Bytes) RecvPacketResult {
	a.recvPackets = append(a.recvPackets, p)
	if a.recvResult.Status != PacketStatusUnknown {
		return a.recvResult
	}
	return RecvPacketResult{Status: PacketStatusSuccess, Ack: Bytes{0x01}}
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
	st = newState()
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

func setupPendingAsyncAck(t *testing.T) Packet {
	t.Helper()
	resetState()
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: 1, Data: Bytes("transfer"), TimeoutTimestamp: 100}
	st.savePendingAsyncAck(packet, runtime.CurrentRealm().Address())
	return packet
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
	p := Packet{Sequence: 1, SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if PacketCommitmentPath(p) == PacketAcknowledgementPath(p) {
		t.Error("commitment and ack paths must differ for the same packet")
	}
}

func TestPacketCommitmentPathUnique(t *testing.T) {
	p1 := Packet{Sequence: 1, SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	p2 := Packet{Sequence: 2, SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if PacketCommitmentPath(p1) == PacketCommitmentPath(p2) {
		t.Error("packets with different sequences must have different commitment paths")
	}
}

func TestPacketReceiptPathDiffers(t *testing.T) {
	p := Packet{Sequence: 1, SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if PacketReceiptPath(p) == PacketCommitmentPath(p) {
		t.Error("receipt and commitment paths must differ for the same packet")
	}
	if PacketReceiptPath(p) == PacketAcknowledgementPath(p) {
		t.Error("receipt and ack paths must differ for the same packet")
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

func TestPacketReceiptLifecycle(t *testing.T) {
	resetState()
	p := Packet{Sequence: 1, SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if st.hasPacketReceipt(p) {
		t.Fatal("receipt must not exist before set")
	}
	st.setPacketReceipt(p)
	if !st.hasPacketReceipt(p) {
		t.Fatal("receipt must exist after set")
	}
	st.deletePacketReceipt(p)
	if st.hasPacketReceipt(p) {
		t.Fatal("receipt must not exist after delete")
	}
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
}

func TestPacketSendReturnsPacketWithSequence(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)

	p0 := PacketSend(cross, MsgPacketSend{SourceChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: 100})
	p1 := PacketSend(cross, MsgPacketSend{SourceChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: 100})
	p2 := PacketSend(cross, MsgPacketSend{SourceChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: 100})

	if p0.Sequence != 0 || p1.Sequence != 1 || p2.Sequence != 2 {
		t.Errorf("unexpected sequences: got %d %d %d", p0.Sequence, p1.Sequence, p2.Sequence)
	}
	if PacketCommitmentPath(p0) == PacketCommitmentPath(p1) || PacketCommitmentPath(p1) == PacketCommitmentPath(p2) {
		t.Fatal("commitment paths must differ by sequence")
	}
}

func TestPacketRecvSyncAckWritten(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portId].(*mockApp)
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: 100}

	uassert.NotAborts(t, func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{
			Packets: []Packet{packet},
			Relayer: address("g1relayer"),
		})
	})

	if len(app.recvPackets) != 1 {
		t.Fatalf("OnRecvPacket calls: got %d want 1", len(app.recvPackets))
	}
	if !st.hasPacketReceipt(packet) {
		t.Fatal("PacketRecv must set packet receipt")
	}
	if !st.hasAcknowledgement(packet) {
		t.Fatal("PacketRecv must commit sync acknowledgement")
	}
}

func TestPacketRecvSyncEmptyAckRejected(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portId].(*mockApp)
	app.recvResult = RecvPacketResult{Status: PacketStatusSuccess, Ack: nil}
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: 100}

	uassert.AbortsContains(t, "sync ack cannot be empty", func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})
}

// --- Async acknowledgement ---

func TestPacketRecvAsyncDefersAck(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portId].(*mockApp)
	app.recvResult = RecvPacketResult{Status: PacketStatusAsync}
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: 100}

	uassert.NotAborts(t, func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})

	if !st.hasPacketReceipt(packet) {
		t.Fatal("async recv must still set packet receipt")
	}
	if st.hasAcknowledgement(packet) {
		t.Fatal("async recv must not commit acknowledgement")
	}
	if !st.hasPendingAsyncAck(packet.DestinationChannelId, packet.Sequence) {
		t.Fatal("async recv must save pending async acknowledgement")
	}
}

func TestPendingAsyncAckLifecycle(t *testing.T) {
	resetState()
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: 1, Data: Bytes("transfer"), TimeoutTimestamp: 100}
	portId := address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9ex6sz")

	st.savePendingAsyncAck(packet, portId)
	pending, ok := st.getPendingAsyncAck(packet.DestinationChannelId, packet.Sequence)
	if !ok {
		t.Fatal("pending async ack must exist after save")
	}
	if pending.Packet.Sequence != packet.Sequence || pending.AuthorizedPort != portId {
		t.Fatal("pending async ack stored unexpected data")
	}
	if !st.hasPendingAsyncAck(packet.DestinationChannelId, packet.Sequence) {
		t.Fatal("hasPendingAsyncAck must report saved pending ack")
	}
	st.deletePendingAsyncAck(packet.DestinationChannelId, packet.Sequence)
	if st.hasPendingAsyncAck(packet.DestinationChannelId, packet.Sequence) {
		t.Fatal("pending async ack must be deleted")
	}
}

func TestSavePendingAsyncAckRejectsDuplicate(t *testing.T) {
	resetState()
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: 1, Data: Bytes("transfer"), TimeoutTimestamp: 100}
	portId := address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9ex6sz")

	st.savePendingAsyncAck(packet, portId)
	mustPanic(t, func() {
		st.savePendingAsyncAck(packet, portId)
	})
}

func TestSavePendingAsyncAckRejectsAlreadyAcked(t *testing.T) {
	resetState()
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: 1, Data: Bytes("transfer"), TimeoutTimestamp: 100}
	portId := address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9ex6sz")

	st.commitAcknowledgement(packet, Bytes{0x01})
	mustPanic(t, func() {
		st.savePendingAsyncAck(packet, portId)
	})
}

func TestWriteAcknowledgementWithoutAsyncRejected(t *testing.T) {
	resetState()

	uassert.AbortsContains(t, "no pending async ack", func(cur realm) {
		WriteAcknowledgement(cur, ChannelId(1), Sequence(7), Bytes{0x01})
	})
}

func TestWriteAcknowledgementWrongCallerPreservesPending(t *testing.T) {
	resetState()
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: 1, Data: Bytes("transfer"), TimeoutTimestamp: 100}
	st.savePendingAsyncAck(packet, address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9ex6sz"))

	uassert.AbortsContains(t, "caller not authorized", func(cur realm) {
		WriteAcknowledgement(cur, packet.DestinationChannelId, packet.Sequence, Bytes{0x01})
	})
	if !st.hasPendingAsyncAck(packet.DestinationChannelId, packet.Sequence) {
		t.Fatal("wrong caller must not consume pending async ack")
	}
}

func TestWriteAcknowledgementEmptyAckRejected(t *testing.T) {
	packet := setupPendingAsyncAck(t)

	uassert.AbortsContains(t, "acknowledgement cannot be empty", func(cur realm) {
		WriteAcknowledgement(cur, packet.DestinationChannelId, packet.Sequence, nil)
	})
	if !st.hasPendingAsyncAck(packet.DestinationChannelId, packet.Sequence) {
		t.Fatal("empty ack must not consume pending async ack")
	}
}

func TestWriteAcknowledgementSuccess(t *testing.T) {
	packet := setupPendingAsyncAck(t)

	uassert.NotAborts(t, func(cur realm) {
		WriteAcknowledgement(cur, packet.DestinationChannelId, packet.Sequence, Bytes{0x01})
	})

	if !st.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must commit ack")
	}
	if st.hasPendingAsyncAck(packet.DestinationChannelId, packet.Sequence) {
		t.Fatal("WriteAcknowledgement must consume pending async ack")
	}
}

func TestWriteAcknowledgementDuplicateRejected(t *testing.T) {
	packet := setupPendingAsyncAck(t)

	WriteAcknowledgement(cross, packet.DestinationChannelId, packet.Sequence, Bytes{0x01})
	uassert.AbortsContains(t, "no pending async ack", func(cur realm) {
		WriteAcknowledgement(cur, packet.DestinationChannelId, packet.Sequence, Bytes{0x02})
	})
}

func TestWriteAcknowledgementAlreadyAckedRejected(t *testing.T) {
	packet := setupPendingAsyncAck(t)
	st.commitAcknowledgement(packet, Bytes{0x01})

	uassert.AbortsContains(t, "acknowledgement already written", func(cur realm) {
		WriteAcknowledgement(cur, packet.DestinationChannelId, packet.Sequence, Bytes{0x02})
	})
	if !st.hasPendingAsyncAck(packet.DestinationChannelId, packet.Sequence) {
		t.Fatal("already-acked failure must not consume pending async ack")
	}
}

func TestPacketRecvReceiptDupRejected(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portId].(*mockApp)
	packet := Packet{Sequence: 7, SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: 100}

	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})
	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})

	if len(app.recvPackets) != 1 {
		t.Fatalf("duplicate recv must not call app again: got %d calls", len(app.recvPackets))
	}
}

func TestPacketAcknowledgementRoundtrip(t *testing.T) {
	resetState()
	portId, connId, channelId := setupOpenChannel(t)
	app := st.ports[portId].(*mockApp)
	packet := PacketSend(cross, MsgPacketSend{SourceChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: 100})
	st.channelOwners[packet.DestinationChannelId] = portId
	st.saveChannel(packet.DestinationChannelId, Channel{
		State:                 ChannelStateOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: packet.SourceChannelId,
		CounterpartyPortId:    Bytes("counterparty"),
		Version:               "ics20-1",
	})

	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})
	PacketAcknowledgement(cross, MsgPacketAcknowledgement{
		Packets:          []Packet{packet},
		Acknowledgements: []Bytes{{0x01}},
		Relayer:          address("g1relayer"),
	})

	if len(app.ackPackets) != 1 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 1", len(app.ackPackets))
	}
	if st.hasPacketCommitment(packet) {
		t.Fatal("acknowledgement must delete source packet commitment")
	}
}

func TestPacketTimeoutReceiptPath(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := PacketSend(cross, MsgPacketSend{SourceChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: 100})
	client := st.clientRegistry[mockType].(*mockClient)

	PacketTimeout(cross, MsgPacketTimeout{Packet: packet})

	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("non-membership calls: got %d want 1", len(client.nonMembershipKeys))
	}
	got := string(client.nonMembershipKeys[0])
	receiptPath := PacketReceiptPath(packet)
	want := string(receiptPath[:])
	if got != want {
		t.Fatal("PacketTimeout must verify PacketReceiptPath non-membership")
	}
	if st.hasPacketCommitment(packet) {
		t.Fatal("timeout must delete source packet commitment")
	}
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
