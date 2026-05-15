package core

import (
	"chain/runtime"
	"encoding/hex"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// --- Mock implementations ---

type mockClient struct {
	chainId                string
	height                 Height
	status                 Status
	membershipClientIds    []ClientId
	membershipHeights      []Height
	membershipProofs       [][]byte
	membershipKeys         [][]byte
	membershipValues       [][]byte
	nonMembershipClientIds []ClientId
	nonMembershipHeights   []Height
	nonMembershipProofs    [][]byte
	nonMembershipKeys      [][]byte
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

func (m *mockClient) VerifyMembership(clientId ClientId, height Height, proof []byte, key []byte, value []byte) {
	m.membershipClientIds = append(m.membershipClientIds, clientId)
	m.membershipHeights = append(m.membershipHeights, height)
	m.membershipProofs = append(m.membershipProofs, proof)
	m.membershipKeys = append(m.membershipKeys, key)
	m.membershipValues = append(m.membershipValues, value)
}

func (m *mockClient) VerifyNonMembership(clientId ClientId, height Height, proof []byte, key []byte) {
	m.nonMembershipClientIds = append(m.nonMembershipClientIds, clientId)
	m.nonMembershipHeights = append(m.nonMembershipHeights, height)
	m.nonMembershipProofs = append(m.nonMembershipProofs, proof)
	m.nonMembershipKeys = append(m.nonMembershipKeys, key)
}
func (m *mockClient) GetTimestamp(_ ClientId, _ Height) Timestamp { return Timestamp(1e9) }
func (m *mockClient) GetLatestHeight(_ ClientId) Height           { return m.height }
func (m *mockClient) GetStatus(_ ClientId) Status                 { return m.status }

type mockApp struct {
	initCalled     bool
	closedChannels []ChannelId
	recvPackets    []Packet
	intentPackets  []Packet
	intentMsgs     [][]byte
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

func (a *mockApp) OnRecvPacket(p Packet, _ address, _ []byte) RecvPacketResult {
	a.recvPackets = append(a.recvPackets, p)
	if a.recvResult.Status != PacketStatusUnknown {
		return a.recvResult
	}
	return RecvPacketResult{Status: PacketStatusSuccess, Ack: []byte{0x01}}
}

func (a *mockApp) OnIntentRecvPacket(p Packet, _ address, msg []byte) {
	a.intentPackets = append(a.intentPackets, p)
	a.intentMsgs = append(a.intentMsgs, msg)
}

func (a *mockApp) OnAcknowledgementPacket(p Packet, _ []byte, _ address) {
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

func assertH256Hex(t *testing.T, name string, got H256, want string) {
	t.Helper()
	if got.String() != want {
		t.Errorf("%s: got %s want %s", name, got.String(), want)
	}
}

func assertBytesHex(t *testing.T, name string, got []byte, want string) {
	t.Helper()
	if hex.EncodeToString(got) != want {
		t.Errorf("%s: got %x want %s", name, got, want)
	}
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}

func setupOpenChannel(t *testing.T) (Bytes, ConnectionId, ChannelId) {
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

	portId := Bytes(runtime.CurrentRealm().PkgPath())
	app := &mockApp{}
	st.ports[portKey(portId)] = app

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
	p2 := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("different"), TimeoutTimestamp: 1000}
	if PacketCommitmentPath(p1) == PacketCommitmentPath(p2) {
		t.Error("packets with different Union payloads must have different commitment paths")
	}
}

func TestBatchReceiptsPathDiffers(t *testing.T) {
	p := Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if BatchReceiptsPath(CommitPacket(p)) == PacketCommitmentPath(p) {
		t.Error("receipt and commitment paths must differ for the same packet")
	}
	if BatchReceiptsPath(CommitPacket(p)) != PacketAcknowledgementPath(p) {
		t.Error("packet acknowledgement path must use Union batch receipts path")
	}
}

func TestUnionPathReferenceVectors(t *testing.T) {
	// Mirrors Union ibc-union-spec path keys:
	// https://github.com/unionlabs/union/blob/main/lib/ibc-union-spec/src/path.rs
	packet := Packet{SourceChannelId: 2, DestinationChannelId: 3, Data: Bytes("abc"), TimeoutTimestamp: 1000}
	batchHash := CommitPackets([]Packet{packet})
	proofPath := []byte("clients/4/clientState")

	assertH256Hex(t, "client state", ClientStatePath(4), "0x17ef568e3e12ab5b9c7254a8d58478811de00f9e6eb34345acd53bf8fd09d3ec")
	assertH256Hex(t, "consensus state", ConsensusStatePath(4, 10), "0xa1776da6f811742b0b6e4f3e386ffa26edc18b9096a5d56e6d8c6366d1f86b32")
	assertH256Hex(t, "connection", ConnectionPath(100), "0x303c03027bd4a34f7fcda516f1651933dbc8cbe20bd53649eb722d1f989225cb")
	assertH256Hex(t, "channel", ChannelPath(7), "0x3be6fd20d5acfde5b873b48692cd31f4d3c7e8ee8a813af4696af8859e5ca6c6")
	assertH256Hex(t, "batch packets", BatchPacketsPath(batchHash), "0x6e9f48cf5c51df29586a27c6219e1168517e3f2dc179371cf7069796ccb01229")
	assertH256Hex(t, "packet commitment", PacketCommitmentPath(packet), BatchPacketsPath(batchHash).String())
	assertH256Hex(t, "batch receipts", BatchReceiptsPath(batchHash), "0x9989767aa720c64326bd2716f9e2b4144d6429d56e8bb523c01b46ed1d17239a")
	assertH256Hex(t, "packet acknowledgement", PacketAcknowledgementPath(packet), BatchReceiptsPath(batchHash).String())
	assertH256Hex(t, "membership proof", MembershipProofPath(4, 10, proofPath), "0x3b320e52a57f28090d6ba22ed1f5b6a3e5df2884e92c9b1df05f407660fd6a27")
	assertH256Hex(t, "non-membership proof", NonMembershipProofPath(4, 10, proofPath), "0x70322f8424ea2964bf16d99caebfc5e38bbcb75d8f2b1b2dfae87a36cb9688b1")
	assertH256Hex(t, "batch timeout", BatchTimeoutPath(packet), "0xb7b713e653ed37563f2260ffcee26b6a8fb5a8b91210373aefcde7b3d36bd0eb")
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

func TestUnionChannelEthABIVector(t *testing.T) {
	// Ported from Union lib/ibc-union-spec/src/types/channel.rs ethabi test.
	channel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          1,
		CounterpartyChannelId: 1,
		CounterpartyPortId:    Bytes{0xde, 0xad, 0xbe, 0xef},
		Version:               "version",
	}
	assertBytesHex(t, "channel ethabi", channel.EthAbiEncode(),
		"0000000000000000000000000000000000000000000000000000000000000001"+
			"0000000000000000000000000000000000000000000000000000000000000001"+
			"0000000000000000000000000000000000000000000000000000000000000001"+
			"00000000000000000000000000000000000000000000000000000000000000a0"+
			"00000000000000000000000000000000000000000000000000000000000000e0"+
			"0000000000000000000000000000000000000000000000000000000000000004"+
			"deadbeef00000000000000000000000000000000000000000000000000000000"+
			"0000000000000000000000000000000000000000000000000000000000000007"+
			"76657273696f6e00000000000000000000000000000000000000000000000000")
}

func TestPacketEthAbiEncodeDistinct(t *testing.T) {
	p1 := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("a"), TimeoutTimestamp: 100}
	p2 := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("b"), TimeoutTimestamp: 100}
	if string(p1.EthAbiEncode()) == string(p2.EthAbiEncode()) {
		t.Error("packets with different data must encode differently")
	}
	p3 := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("a"), TimeoutHeight: 1, TimeoutTimestamp: 100}
	uassert.AbortsContains(t, "packet timeout height must be zero", func(cur realm) { p3.EthAbiEncode() })
}

func TestPacketHashUnionReferenceVector(t *testing.T) {
	// Ported from Union lib/ibc-union-spec/src/types/packet.rs packet_hash test.
	packet := Packet{
		SourceChannelId:      1,
		DestinationChannelId: 9,
		Data: Bytes(mustHex(
			"ef2adec1b178443b9d06bb585939028d1d145463a272874f4188833bda0590bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000078000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000014d1120d7b1600000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000014d1120d7b16000000000000000000000000000000000000000000000000000000000000000000014bd1b743615f903a630393f78234b4500fbe5691a000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a3078326336443733663430414365353132433433303430324463624463393438393431343330353034380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000142be4bf88014a6574cb10df3b7826be8356aa24990000000000000000000000000000000000000000000000000000000000000000000000000000000000000007756e694254436400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b756e694254432044656d6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e62626e31683867717a763638713334723073386471343770756171726b6e74343835303533793330647235636a30667964766c307a7839716a7278617868000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000001f4000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014bd1b743615f903a630393f78234b4500fbe5691a000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a307832633644373366343041436535313243343330343032446362446339343839343134333035303438000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014420000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000045745544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e62626e31647530393867637661617234657573667a703035717070657433333879716339793637776338663574613472666d7978733734736a72683639730000",
		)),
		TimeoutTimestamp: 9007199254740991,
	}
	assertH256Hex(t, "packet hash", CommitPacket(packet), "0xb204ec01ba72d32b884df0ecbfea727a15c82c1e0a08dff53fde4990d3ba589f")
}

// --- State: client registry ---

func TestClientRegistryStoresClient(t *testing.T) {
	resetState()
	c := &mockClient{chainId: "union-1"}
	st.registerClient(mockType, c)
	if _, ok := st.clientRegistry[mockType]; !ok {
		t.Error("client not found in registry after registration")
	}
}

func TestClientRegistryDuplicatePanics(t *testing.T) {
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

func TestGetClientStateReturnsStoredBytes(t *testing.T) {
	resetState()
	st.saveClientState(ClientId(1), []byte("client-state"))

	got := QueryClientState(ClientId(1))
	if got != "0x636c69656e742d7374617465" {
		t.Errorf("GetClientState: got %q want hex client-state", got)
	}
}

func TestQueryClientStateUnknownReturnsEmpty(t *testing.T) {
	resetState()

	got := QueryClientState(ClientId(999))
	if got != "" {
		t.Errorf("QueryClientState: got %q want empty", got)
	}
}

func TestGetClientTypeReturnsRegisteredType(t *testing.T) {
	resetState()
	st.clientTypes[ClientId(1)] = mockType

	got := GetClientType(ClientId(1))
	if got != string(mockType) {
		t.Errorf("GetClientType: got %q want %q", got, string(mockType))
	}
}

func TestGetClientTypeUnknownReturnsEmpty(t *testing.T) {
	resetState()

	got := GetClientType(ClientId(999))
	if got != "" {
		t.Errorf("GetClientType: got %q want empty", got)
	}
}

func TestGetConsensusStateReturnsStoredBytes(t *testing.T) {
	resetState()
	st.saveConsensusState(ClientId(1), Height(10), []byte("consensus-state"))

	got := QueryConsensusState(ClientId(1), Height(10))
	if got != "0x636f6e73656e7375732d7374617465" {
		t.Errorf("GetConsensusState: got %q want hex consensus-state", got)
	}
}

func TestQueryConsensusStateUnknownReturnsEmpty(t *testing.T) {
	resetState()
	st.saveConsensusState(ClientId(1), Height(10), []byte("consensus-state"))

	if got := QueryConsensusState(ClientId(999), Height(10)); got != "" {
		t.Errorf("QueryConsensusState unknown client: got %q want empty", got)
	}
	if got := QueryConsensusState(ClientId(1), Height(999)); got != "" {
		t.Errorf("QueryConsensusState unknown height: got %q want empty", got)
	}
}

func TestCreateClientStoresInitialClientAndConsensusState(t *testing.T) {
	resetState()
	st.clientRegistry[mockType] = &mockClient{chainId: "union-1", height: 100}

	clientId := CreateClient(cross, MsgCreateClient{
		ClientType:          mockType,
		ClientStateBytes:    []byte("client-state"),
		ConsensusStateBytes: []byte("consensus-state"),
	})

	if got := QueryClientState(clientId); got != "0x636c69656e742d7374617465" {
		t.Errorf("GetClientState: got %q want hex client-state", got)
	}
	if got := QueryConsensusState(clientId, Height(100)); got != "0x636f6e73656e7375732d7374617465" {
		t.Errorf("GetConsensusState: got %q want hex consensus-state", got)
	}
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

	want := hexString(conn.EthAbiEncode())
	if got := QueryConnection(id); got != want {
		t.Errorf("QueryConnection: got %q want %q", got, want)
	}
}

func TestGetConnectionNotFoundPanics(t *testing.T) {
	resetState()
	mustPanic(t, func() { st.getConnection(ConnectionId(999)) })
}

func TestQueryConnectionUnknownReturnsEmpty(t *testing.T) {
	resetState()

	got := QueryConnection(ConnectionId(999))
	if got != "" {
		t.Errorf("QueryConnection: got %q want empty", got)
	}
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

	want := hexString(ch.EthAbiEncode())
	if got := QueryChannel(id); got != want {
		t.Errorf("QueryChannel: got %q want %q", got, want)
	}
}

func TestGetChannelNotFoundPanics(t *testing.T) {
	resetState()
	mustPanic(t, func() { st.getChannel(ChannelId(999)) })
}

func TestQueryChannelUnknownReturnsEmpty(t *testing.T) {
	resetState()

	got := QueryChannel(ChannelId(999))
	if got != "" {
		t.Errorf("QueryChannel: got %q want empty", got)
	}
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

func TestPacketSendCommitsPacket(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)

	packet := PacketSend(cross, channelId, 0, 100, []byte("data"))

	if packet.SourceChannelId != channelId {
		t.Fatal("PacketSend must preserve source channel")
	}
	if packet.DestinationChannelId != st.getChannel(channelId).CounterpartyChannelId {
		t.Fatal("PacketSend must use channel counterparty as destination")
	}
	if !st.hasPacketCommitment(packet) {
		t.Fatal("PacketSend must commit packet")
	}
}

func TestPacketSendRejectsNonOwner(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	st.channelOwners[channelId] = Bytes("g1notchannelowner")

	uassert.AbortsContains(t, "caller not authorized to send packet", func(cur realm) {
		PacketSend(cur, channelId, 0, 100, []byte("data"))
	})
}

func TestPacketSendRejectsAddressAsPortId(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	// Port registered with address (old behavior) must be rejected when caller's
	// PkgPath is compared instead.
	st.channelOwners[channelId] = Bytes(runtime.CurrentRealm().Address().String())

	uassert.AbortsContains(t, "caller not authorized to send packet", func(cur realm) {
		PacketSend(cur, channelId, 0, 100, []byte("data"))
	})
}

func TestBatchSendReturnsUnionPacketCommitment(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("a"), TimeoutTimestamp: 100}
	p2 := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("b"), TimeoutTimestamp: 100}

	got := BatchSend(cross, MsgBatchSend{Packets: []Packet{p1, p2}})
	want := CommitPackets([]Packet{p1, p2})
	if got != want {
		t.Fatal("BatchSend must return Union packet batch commitment")
	}
	if got := QueryBatchPackets(want); got != COMMITMENT_MAGIC.String() {
		t.Errorf("GetBatchPackets: got %s want %s", got, COMMITMENT_MAGIC)
	}
}

func TestQueryBatchPacketsUnknownReturnsEmpty(t *testing.T) {
	resetState()

	var batchHash H256
	got := QueryBatchPackets(batchHash)
	if got != "" {
		t.Errorf("QueryBatchPackets: got %q want empty", got)
	}
}

func TestBatchSendRejectsEmptyPacketList(t *testing.T) {
	resetState()
	uassert.AbortsContains(t, "not enough packets", func(cur realm) {
		BatchSend(cur, MsgBatchSend{})
	})
}

func TestBatchSendRejectsNonOwner(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	st.channelOwners[channelId] = Bytes("gno.land/r/not-channel-owner")
	packet := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("a"), TimeoutTimestamp: 100}

	uassert.AbortsContains(t, "caller not authorized to send packet", func(cur realm) {
		BatchSend(cur, MsgBatchSend{Packets: []Packet{packet}})
	})
}

func TestBatchAcksReturnsUnionPacketCommitment(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: 100}
	p2 := Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: Bytes("b"), TimeoutTimestamp: 100}

	got := BatchAcks(cross, MsgBatchAcks{
		Packets: []Packet{p1, p2},
		Acks:    [][]byte{[]byte("ack-a"), []byte("ack-b")},
	})
	want := CommitPackets([]Packet{p1, p2})
	if got != want {
		t.Fatal("BatchAcks must return Union packet batch commitment")
	}
	wantAck := CommitAcks([][]byte{[]byte("ack-a"), []byte("ack-b")})
	if got := QueryBatchReceipts(want); got != wantAck.String() {
		t.Errorf("GetBatchReceipts: got %s want %s", got, wantAck)
	}
}

func TestQueryBatchReceiptsUnknownReturnsEmpty(t *testing.T) {
	resetState()

	var batchHash H256
	got := QueryBatchReceipts(batchHash)
	if got != "" {
		t.Errorf("QueryBatchReceipts: got %q want empty", got)
	}
}

func TestBatchAcksRejectsAckCountMismatch(t *testing.T) {
	resetState()
	p := Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: Bytes("a"), TimeoutTimestamp: 100}
	uassert.AbortsContains(t, "acknowledgement count mismatch", func(cur realm) {
		BatchAcks(cur, MsgBatchAcks{Packets: []Packet{p}, Acks: [][]byte{}})
	})
}

func TestBatchAcksRejectsNonOwner(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	st.channelOwners[channelId] = Bytes("gno.land/r/not-channel-owner")
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: 100}

	uassert.AbortsContains(t, "caller not authorized to write ack", func(cur realm) {
		BatchAcks(cur, MsgBatchAcks{Packets: []Packet{packet}, Acks: [][]byte{[]byte("ack")}})
	})
}

func TestPacketReceiptLifecycle(t *testing.T) {
	resetState()
	p := Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
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
		st.getAppByPortId(Bytes("g1missing"))
	})
}

func TestGetChannelOwnerPanicsWhenMissing(t *testing.T) {
	resetState()
	mustPanic(t, func() {
		st.getChannelOwner(ChannelId(999))
	})
}

// --- Integration: packet send lifecycle ---

func TestPacketCommitmentLifecycle(t *testing.T) {
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

func TestPacketRecvSyncAckWritten(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{
			Packets: []Packet{packet},
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

func TestPacketRecvBatchUsesUnionBatchCommitment(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	client := st.clientRegistry[mockType].(*mockClient)
	p1 := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}
	proof := Bytes("batch-proof")

	PacketRecv(cross, MsgPacketRecv{
		Packets:     []Packet{p1, p2},
		RelayerMsgs: [][]byte{[]byte("relay-a"), []byte("relay-b")},
		Proof:       proof,
		ProofHeight: Height(10),
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	batchHash := CommitPackets([]Packet{p1, p2})
	batchPath := BatchPacketsPath(batchHash)
	if string(client.membershipKeys[0]) != string(batchPath[:]) {
		t.Fatal("PacketRecv must verify Union batch packets path")
	}
	if string(client.membershipValues[0]) != string(COMMITMENT_MAGIC[:]) {
		t.Fatal("PacketRecv must verify commitment magic for batch packet membership")
	}
	if client.membershipHeights[0] != Height(10) || string(client.membershipProofs[0]) != string(proof) {
		t.Fatal("PacketRecv must pass batch proof height and bytes through")
	}
	if len(app.recvPackets) != 2 {
		t.Fatalf("OnRecvPacket calls: got %d want 2", len(app.recvPackets))
	}
	if !st.hasPacketReceipt(p1) || !st.hasPacketReceipt(p2) {
		t.Fatal("PacketRecv must set receipt for every batch packet")
	}
}

func TestPacketRecvBatchRejectsDifferentDestinationChannel(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	otherChannelId := st.generateChannelId()
	st.saveChannel(otherChannelId, Channel{State: ChannelStateOpen})
	p1 := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := Packet{SourceChannelId: 99, DestinationChannelId: otherChannelId, Data: Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, "batch must use the same channel", func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{p1, p2}})
	})
}

func TestPacketRecvSyncEmptyAckRejected(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = RecvPacketResult{Status: PacketStatusSuccess, Ack: nil}
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, "sync ack cannot be empty", func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})
}

// --- Async acknowledgement ---

func TestPacketRecvAsyncDefersAck(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = RecvPacketResult{Status: PacketStatusAsync}
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})

	if !st.hasPacketReceipt(packet) {
		t.Fatal("async recv must still set packet receipt")
	}
	if st.hasAcknowledgement(packet) {
		t.Fatal("async recv must not commit acknowledgement")
	}
}

func TestWriteAcknowledgementCommitsAsyncAck(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = RecvPacketResult{Status: PacketStatusAsync}
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})
	WriteAcknowledgement(cross, MsgWriteAcknowledgement{
		Packet:          packet,
		Acknowledgement: []byte("async-ack"),
	})

	if !st.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must commit acknowledgement")
	}
}

func TestWriteAcknowledgementRejectsNonOwner(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = RecvPacketResult{Status: PacketStatusAsync}
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})
	st.channelOwners[channelId] = Bytes("g1notchannelowner")

	uassert.AbortsContains(t, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cur, MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsAddressAsPortId(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = RecvPacketResult{Status: PacketStatusAsync}
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})
	// Port registered with address (old behavior) must be rejected.
	st.channelOwners[channelId] = Bytes(runtime.CurrentRealm().Address().String())

	uassert.AbortsContains(t, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cur, MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsAlreadyAcked(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: 100}

	st.commitAcknowledgement(packet, []byte("ack"))

	uassert.AbortsContains(t, "acknowledgement already written", func(cur realm) {
		WriteAcknowledgement(cur, MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestPacketRecvReceiptDupRejected(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})
	PacketRecv(cross, MsgPacketRecv{Packets: []Packet{packet}})

	if len(app.recvPackets) != 1 {
		t.Fatalf("duplicate recv must not call app again: got %d calls", len(app.recvPackets))
	}
}

func TestIntentPacketRecvDispatchesAndSetsReceipt(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, func(cur realm) {
		IntentPacketRecv(cur, MsgIntentPacketRecv{
			Packets:             []Packet{packet},
			MarketMakerMessages: [][]byte{[]byte("maker-msg")},
		})
	})

	if len(app.intentPackets) != 1 {
		t.Fatalf("OnIntentRecvPacket calls: got %d want 1", len(app.intentPackets))
	}
	if string(app.intentMsgs[0]) != "maker-msg" {
		t.Fatalf("market maker msg: got %q", string(app.intentMsgs[0]))
	}
	if !st.hasPacketReceipt(packet) {
		t.Fatal("IntentPacketRecv must set packet receipt")
	}
	if st.hasAcknowledgement(packet) {
		t.Fatal("IntentPacketRecv must not write an acknowledgement")
	}
}

func TestIntentPacketRecvDuplicateSkipped(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	IntentPacketRecv(cross, MsgIntentPacketRecv{Packets: []Packet{packet}})
	IntentPacketRecv(cross, MsgIntentPacketRecv{Packets: []Packet{packet}})

	if len(app.intentPackets) != 1 {
		t.Fatalf("duplicate intent recv must not call app again: got %d calls", len(app.intentPackets))
	}
}

func TestPacketAcknowledgementRoundtrip(t *testing.T) {
	resetState()
	portId, connId, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}
	st.commitPacket(packet)
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
		Acknowledgements: [][]byte{{0x01}},
	})

	if len(app.ackPackets) != 1 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 1", len(app.ackPackets))
	}
	if st.hasPacketCommitment(packet) {
		t.Fatal("acknowledgement must delete source packet commitment")
	}
}

func TestPacketAcknowledgementBatchUsesUnionBatchReceipts(t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	client := st.clientRegistry[mockType].(*mockClient)
	p1 := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("a"), TimeoutTimestamp: 100}
	p2 := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("b"), TimeoutTimestamp: 100}
	st.commitPacket(p1)
	st.commitPacket(p2)
	acks := [][]byte{{0x01}, {0x02}}
	proof := Bytes("ack-proof")

	PacketAcknowledgement(cross, MsgPacketAcknowledgement{
		Packets:          []Packet{p1, p2},
		Acknowledgements: acks,
		Proof:            proof,
		ProofHeight:      Height(10),
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	batchHash := CommitPackets([]Packet{p1, p2})
	receiptPath := BatchReceiptsPath(batchHash)
	if string(client.membershipKeys[0]) != string(receiptPath[:]) {
		t.Fatal("PacketAcknowledgement must verify Union batch receipts path")
	}
	ackValue := CommitAcks(acks)
	if string(client.membershipValues[0]) != string(ackValue[:]) {
		t.Fatal("PacketAcknowledgement must verify Union batch ack value")
	}
	if client.membershipHeights[0] != Height(10) || string(client.membershipProofs[0]) != string(proof) {
		t.Fatal("PacketAcknowledgement must pass batch proof height and bytes through")
	}
	if len(app.ackPackets) != 2 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 2", len(app.ackPackets))
	}
	if st.hasPacketCommitment(p1) || st.hasPacketCommitment(p2) {
		t.Fatal("PacketAcknowledgement must delete every batch packet commitment")
	}
}

func TestPacketAcknowledgementBatchRejectsDifferentSourceChannel(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	otherChannelId := st.generateChannelId()
	st.saveChannel(otherChannelId, Channel{State: ChannelStateOpen})
	p1 := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("a"), TimeoutTimestamp: 100}
	p2 := Packet{SourceChannelId: otherChannelId, DestinationChannelId: 99, Data: Bytes("b"), TimeoutTimestamp: 100}
	st.commitPacket(p1)
	st.commitPacket(p2)

	uassert.AbortsContains(t, "batch must use the same channel", func(cur realm) {
		PacketAcknowledgement(cur, MsgPacketAcknowledgement{
			Packets:          []Packet{p1, p2},
			Acknowledgements: [][]byte{{0x01}, {0x02}},
		})
	})
}

func TestPacketTimeoutReceiptPath(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("transfer"), TimeoutTimestamp: 100}
	st.commitPacket(packet)
	client := st.clientRegistry[mockType].(*mockClient)

	PacketTimeout(cross, MsgPacketTimeout{Packet: packet})

	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("non-membership calls: got %d want 1", len(client.nonMembershipKeys))
	}
	got := string(client.nonMembershipKeys[0])
	receiptPath := BatchReceiptsPath(CommitPacket(packet))
	want := string(receiptPath[:])
	if got != want {
		t.Fatal("PacketTimeout must verify Union batch receipt non-membership")
	}
	if st.hasPacketCommitment(packet) {
		t.Fatal("timeout must delete source packet commitment")
	}
}

func TestCommitMembershipProofVerifiesUnionPathValue(t *testing.T) {
	resetState()
	client := &mockClient{chainId: "union-1", status: StatusActive}
	st.clientRegistry[mockType] = client
	st.clientTypes[ClientId(4)] = mockType

	path := Bytes("clients/4/clientState")
	value := Bytes("client-state")
	proof := Bytes("membership-proof")
	CommitMembershipProof(cross, MsgCommitMembershipProof{
		ClientId:    ClientId(4),
		ProofHeight: Height(10),
		Proof:       proof,
		Path:        path,
		Value:       value,
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipClientIds[0] != ClientId(4) || client.membershipHeights[0] != Height(10) {
		t.Fatal("CommitMembershipProof must pass client id and proof height through")
	}
	if string(client.membershipProofs[0]) != string(proof) ||
		string(client.membershipKeys[0]) != string(path) ||
		string(client.membershipValues[0]) != string(value) {
		t.Fatal("CommitMembershipProof must verify caller supplied proof path and value")
	}
}

func TestVerifyClientMembershipVerifiesUnionPathValue(t *testing.T) {
	resetState()
	client := &mockClient{chainId: "union-1", status: StatusActive}
	st.clientRegistry[mockType] = client
	st.clientTypes[ClientId(4)] = mockType

	path := Bytes("clients/7/consensusStates/11")
	value := Bytes("consensus-state")
	proof := Bytes("membership-proof")
	VerifyClientMembership(cross, ClientId(4), Height(10), proof, path, value)

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipClientIds[0] != ClientId(4) || client.membershipHeights[0] != Height(10) {
		t.Fatal("VerifyClientMembership must pass client id and proof height through")
	}
	if string(client.membershipProofs[0]) != string(proof) ||
		string(client.membershipKeys[0]) != string(path) ||
		string(client.membershipValues[0]) != string(value) {
		t.Fatal("VerifyClientMembership must pass proof path and value through")
	}
}

func TestGetClientStatusDelegatesToClient(t *testing.T) {
	resetState()
	st.clientRegistry[mockType] = &mockClient{chainId: "union-1", status: StatusFrozen}
	st.clientTypes[ClientId(4)] = mockType

	if got := GetClientStatus(ClientId(4)); got != StatusFrozen {
		t.Fatalf("GetClientStatus: got %d want %d", got, StatusFrozen)
	}
}

func TestGetClientStatusReturnsUnknownForMissingClient(t *testing.T) {
	resetState()

	if got := GetClientStatus(ClientId(5)); got != StatusUnknown {
		t.Fatalf("GetClientStatus missing: got %d want %d", got, StatusUnknown)
	}
}

func TestCommitNonMembershipProofVerifiesUnionPath(t *testing.T) {
	resetState()
	client := &mockClient{chainId: "union-1", status: StatusActive}
	st.clientRegistry[mockType] = client
	st.clientTypes[ClientId(4)] = mockType

	path := Bytes("clients/4/clientState")
	proof := Bytes("non-membership-proof")
	CommitNonMembershipProof(cross, MsgCommitNonMembershipProof{
		ClientId:    ClientId(4),
		ProofHeight: Height(10),
		Proof:       proof,
		Path:        path,
	})

	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("non-membership calls: got %d want 1", len(client.nonMembershipKeys))
	}
	if client.nonMembershipClientIds[0] != ClientId(4) || client.nonMembershipHeights[0] != Height(10) {
		t.Fatal("CommitNonMembershipProof must pass client id and proof height through")
	}
	if string(client.nonMembershipProofs[0]) != string(proof) ||
		string(client.nonMembershipKeys[0]) != string(path) {
		t.Fatal("CommitNonMembershipProof must verify caller supplied proof path")
	}
}

func TestCommitPacketTimeoutVerifiesUnionBatchTimeoutPath(t *testing.T) {
	resetState()
	_, connId, channelId := setupOpenChannel(t)
	client := st.clientRegistry[mockType].(*mockClient)
	packet := Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: Bytes("transfer"), TimeoutTimestamp: 100}
	proof := Bytes("timeout-proof")

	CommitPacketTimeout(cross, MsgCommitPacketTimeout{
		Packet:      packet,
		ProofHeight: Height(10),
		Proof:       proof,
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipHeights[0] != Height(10) {
		t.Fatal("CommitPacketTimeout must pass proof height through")
	}
	if string(client.membershipProofs[0]) != string(proof) {
		t.Fatal("CommitPacketTimeout must pass proof bytes through")
	}
	timeoutPath := BatchTimeoutPath(packet)
	if string(client.membershipKeys[0]) != string(timeoutPath[:]) {
		t.Fatal("CommitPacketTimeout must verify Union batch timeout path")
	}
	if string(client.membershipValues[0]) != string(COMMITMENT_MAGIC[:]) {
		t.Fatal("CommitPacketTimeout must verify commitment magic value")
	}
	_ = connId
}

// --- Integration: channel close ---

func TestUnionChannelCloseDatagramsUnsupported(t *testing.T) {
	resetState()
	uassert.AbortsContains(t, "Union MsgChannelCloseInit has no channel id", func(cur realm) {
		ChannelCloseInit(cur, MsgChannelCloseInit{})
	})
	uassert.AbortsContains(t, "Union MsgChannelCloseConfirm has no channel id", func(cur realm) {
		ChannelCloseConfirm(cur, MsgChannelCloseConfirm{})
	})
}
