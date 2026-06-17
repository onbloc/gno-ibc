package core

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// --- Helpers ---

const (
	mockType        types.ClientType = "mock"
	testCorePkgPath                  = "gno.land/r/onbloc/ibc/union/core"
	oldAddressPort                   = "g1vjt8cj2s6f5w4sly0s2l0vh85k0y8jyz3f8qzss"
)

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

func assertH256Hex(t *testing.T, name string, got types.H256, want string) {
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

func assertStringSliceEqual(t *testing.T, got []string, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("attribute count: got %d want %d; attrs=%v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("attr[%d]: got %q want %q; attrs=%v", i, got[i], want[i], got)
		}
	}
}

func assertAttrMissing(t *testing.T, attrs []string, key string) {
	t.Helper()
	for i := 0; i+1 < len(attrs); i += 2 {
		if attrs[i] == key {
			t.Fatalf("attribute %q present with value %q", key, attrs[i+1])
		}
	}
}

func assertAttrEqual(t *testing.T, attrs []string, key string, want string) {
	t.Helper()
	for i := 0; i+1 < len(attrs); i += 2 {
		if attrs[i] == key {
			if attrs[i+1] != want {
				t.Fatalf("attribute %q: got %q want %q", key, attrs[i+1], want)
			}
			return
		}
	}
	t.Fatalf("attribute %q missing", key)
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}

func mustEncodeABI(bz []byte, err error) []byte {
	if err != nil {
		panic(err)
	}
	return bz
}

func setupOpenChannel(t *testing.T) (types.Bytes, types.ConnectionId, types.ChannelId) {
	t.Helper()
	clientId := st.generateClientId()
	st.clientTypes[clientId] = mockType
	st.clientRegistry[mockType] = &mockClient{chainId: "union-1", height: types.NewHeight(100), status: types.StatusActive}

	connId := st.generateConnectionId()
	st.saveConnection(connId, types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(99),
	})

	portId := types.Bytes(testCorePkgPath)
	app := &mockApp{}
	st.ports[portKey(portId)] = app

	channelId := st.generateChannelId()
	st.channelOwners[channelId] = portId
	st.saveChannel(channelId, types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: types.ChannelId(99),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	})
	return portId, connId, channelId
}

// --- Path tests ---

func TestClientStatePathUnique(cur realm, t *testing.T) {
	if types.ClientStatePath(1) == types.ClientStatePath(2) {
		t.Error("different client IDs must produce different paths")
	}
	if types.ClientStatePath(1) != types.ClientStatePath(1) {
		t.Error("same client ID must produce same path")
	}
}

func TestConsensusStatePathUnique(cur realm, t *testing.T) {
	if types.ConsensusStatePath(1, types.NewHeight(10)) == types.ConsensusStatePath(1, types.NewHeight(11)) {
		t.Error("different heights must produce different paths")
	}
	if types.ConsensusStatePath(1, types.NewHeight(10)) == types.ConsensusStatePath(2, types.NewHeight(10)) {
		t.Error("different client IDs must produce different paths")
	}
}

func TestConnectionChannelPathUnique(cur realm, t *testing.T) {
	if types.ConnectionPath(1) == types.ConnectionPath(2) {
		t.Error("different connection IDs must produce different paths")
	}
	if types.ChannelPath(1) == types.ChannelPath(2) {
		t.Error("different channel IDs must produce different paths")
	}
	if types.ConnectionPath(1) == types.ChannelPath(1) {
		t.Error("connection and channel paths for same ID must differ")
	}
}

func TestPacketCommitmentAndAckPathsDiffer(cur realm, t *testing.T) {
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if types.MustCommit(types.PacketCommitmentPath(p)) == types.MustCommit(types.PacketAcknowledgementPath(p)) {
		t.Error("commitment and ack paths must differ for the same packet")
	}
}

func TestPacketCommitmentPathUnique(cur realm, t *testing.T) {
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("different"), TimeoutTimestamp: 1000}
	if types.MustCommit(types.PacketCommitmentPath(p1)) == types.MustCommit(types.PacketCommitmentPath(p2)) {
		t.Error("packets with different Union payloads must have different commitment paths")
	}
}

func TestBatchReceiptsPathDiffers(cur realm, t *testing.T) {
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if types.BatchReceiptsPath(types.MustCommit(types.CommitPacket(p))) == types.MustCommit(types.PacketCommitmentPath(p)) {
		t.Error("receipt and commitment paths must differ for the same packet")
	}
	if types.BatchReceiptsPath(types.MustCommit(types.CommitPacket(p))) != types.MustCommit(types.PacketAcknowledgementPath(p)) {
		t.Error("packet acknowledgement path must use Union batch receipts path")
	}
}

func TestUnionPathReferenceVectors(cur realm, t *testing.T) {
	// Mirrors Union ibc-union-spec path keys:
	// https://github.com/unionlabs/union/blob/main/lib/ibc-union-spec/src/path.rs
	packet := types.Packet{SourceChannelId: 2, DestinationChannelId: 3, Data: types.Bytes("abc"), TimeoutTimestamp: 1000}
	batchHash := types.MustCommit(types.CommitPackets([]types.Packet{packet}))

	assertH256Hex(t, "client state", types.ClientStatePath(4), "0x17ef568e3e12ab5b9c7254a8d58478811de00f9e6eb34345acd53bf8fd09d3ec")
	assertH256Hex(t, "consensus state", types.ConsensusStatePath(4, types.NewHeight(10)), "0xa1776da6f811742b0b6e4f3e386ffa26edc18b9096a5d56e6d8c6366d1f86b32")
	assertH256Hex(t, "connection", types.ConnectionPath(100), "0x303c03027bd4a34f7fcda516f1651933dbc8cbe20bd53649eb722d1f989225cb")
	assertH256Hex(t, "channel", types.ChannelPath(7), "0x3be6fd20d5acfde5b873b48692cd31f4d3c7e8ee8a813af4696af8859e5ca6c6")
	assertH256Hex(t, "batch packets", types.BatchPacketsPath(batchHash), "0x6e9f48cf5c51df29586a27c6219e1168517e3f2dc179371cf7069796ccb01229")
	assertH256Hex(t, "packet commitment", types.MustCommit(types.PacketCommitmentPath(packet)), types.BatchPacketsPath(batchHash).String())
	assertH256Hex(t, "batch receipts", types.BatchReceiptsPath(batchHash), "0x9989767aa720c64326bd2716f9e2b4144d6429d56e8bb523c01b46ed1d17239a")
	assertH256Hex(t, "packet acknowledgement", types.MustCommit(types.PacketAcknowledgementPath(packet)), types.BatchReceiptsPath(batchHash).String())
}

// --- Type encoding tests ---

func TestConnectionEncodeABIDistinct(cur realm, t *testing.T) {
	open := types.Connection{State: types.ConnectionStateOpen, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
	init := types.Connection{State: types.ConnectionStateInit, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
	if string(mustEncodeABI(open.EncodeABI())) == string(mustEncodeABI(init.EncodeABI())) {
		t.Error("different connection states must encode differently")
	}
}

func TestChannelEncodeABIDistinct(cur realm, t *testing.T) {
	open := types.Channel{State: types.ChannelStateOpen, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"}
	closed := types.Channel{State: types.ChannelStateClosed, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"}
	if string(mustEncodeABI(open.EncodeABI())) == string(mustEncodeABI(closed.EncodeABI())) {
		t.Error("different channel states must encode differently")
	}
}

func TestUnionChannelEthABIVector(cur realm, t *testing.T) {
	// Ported from Union lib/ibc-union-spec/src/types/channel.rs ethabi test.
	channel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          1,
		CounterpartyChannelId: 1,
		CounterpartyPortId:    types.Bytes{0xde, 0xad, 0xbe, 0xef},
		Version:               "version",
	}
	assertBytesHex(t, "channel ethabi", mustEncodeABI(channel.EncodeABI()),
		"0000000000000000000000000000000000000000000000000000000000000020"+
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

func TestIntegrationCase(cur realm, t *testing.T) {
	channel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          3,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    types.Bytes(mustHex("5fbe74a283f7954f10aa04c2edf55578811aeb03")),
		Version:               "ucs03-zkgm-0",
	}
	assertH256Hex(t, "channel commitment", keccak(mustEncodeABI(channel.EncodeABI())), "0x00781657f014fd25772f10edb002612aa3839e958adf1aa1d2c0f7a44758da26")
}

func TestPacketEncodeABIDistinct(cur realm, t *testing.T) {
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	if string(mustEncodeABI(p1.EncodeABI())) == string(mustEncodeABI(p2.EncodeABI())) {
		t.Error("packets with different data must encode differently")
	}
}

func TestPacketHashUnionReferenceVector(cur realm, t *testing.T) {
	// Ported from Union lib/ibc-union-spec/src/types/packet.rs packet_hash test.
	packet := types.Packet{
		SourceChannelId:      1,
		DestinationChannelId: 9,
		Data: types.Bytes(mustHex(
			"ef2adec1b178443b9d06bb585939028d1d145463a272874f4188833bda0590bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000078000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000014d1120d7b1600000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000014d1120d7b16000000000000000000000000000000000000000000000000000000000000000000014bd1b743615f903a630393f78234b4500fbe5691a000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a3078326336443733663430414365353132433433303430324463624463393438393431343330353034380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000142be4bf88014a6574cb10df3b7826be8356aa24990000000000000000000000000000000000000000000000000000000000000000000000000000000000000007756e694254436400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b756e694254432044656d6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e62626e31683867717a763638713334723073386471343770756171726b6e74343835303533793330647235636a30667964766c307a7839716a7278617868000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000001f4000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014bd1b743615f903a630393f78234b4500fbe5691a000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a307832633644373366343041436535313243343330343032446362446339343839343134333035303438000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014420000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000045745544800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e62626e31647530393867637661617234657573667a703035717070657433333879716339793637776338663574613472666d7978733734736a72683639730000",
		)),
		TimeoutTimestamp: 9007199254740991,
	}
	assertH256Hex(t, "packet hash", types.MustCommit(types.CommitPacket(packet)), "0xb204ec01ba72d32b884df0ecbfea727a15c82c1e0a08dff53fde4990d3ba589f")
}

// --- State: client registry ---

func TestClientRegistryStoresClient(cur realm, t *testing.T) {
	resetState()
	c := &mockClient{chainId: "union-1"}
	st.registerClient(mockType, c)
	if _, ok := st.clientRegistry[mockType]; !ok {
		t.Error("client not found in registry after registration")
	}
}

func TestClientRegistryDuplicatePanics(cur realm, t *testing.T) {
	resetState()
	st.registerClient(mockType, &mockClient{})
	mustPanic(t, func() {
		st.registerClient(mockType, &mockClient{})
	})
}

func TestRegisterClientRejectsDuplicateType(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewCodeRealm(testCorePkgPath))
	clientType := types.ClientType(testCorePkgPath + "/testing/immutable-client")

	RegisterClient(cur, clientType, &mockClient{chainId: "first"})
	uassert.True(t, HasClient(clientType))

	// Light-client implementations are immutable for a registered type. The
	// upgrade path is a new types.ClientType plus channel migration, not replacement.
	uassert.AbortsContains(t, cur, "client type already registered", func(cur realm) {
		RegisterClient(cur, clientType, &mockClient{chainId: "second"})
	})
}

func TestGetClientNotFoundPanics(cur realm, t *testing.T) {
	resetState()
	mustPanic(t, func() {
		st.getClient(types.ClientId(999))
	})
}

func TestGetClientStateReturnsStoredBytes(cur realm, t *testing.T) {
	resetState()
	st.saveClientState(types.ClientId(1), []byte("client-state"))

	got := QueryClientState(types.ClientId(1))
	if got != "0x636c69656e742d7374617465" {
		t.Errorf("GetClientState: got %q want hex client-state", got)
	}
}

func TestQueryClientStateUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	got := QueryClientState(types.ClientId(999))
	if got != "" {
		t.Errorf("QueryClientState: got %q want empty", got)
	}
}

func TestGetClientTypeReturnsRegisteredType(cur realm, t *testing.T) {
	resetState()
	st.clientTypes[types.ClientId(1)] = mockType

	got := GetClientType(types.ClientId(1))
	if got != string(mockType) {
		t.Errorf("GetClientType: got %q want %q", got, string(mockType))
	}
}

func TestGetClientTypeUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	got := GetClientType(types.ClientId(999))
	if got != "" {
		t.Errorf("GetClientType: got %q want empty", got)
	}
}

func TestGetConsensusStateReturnsStoredBytes(cur realm, t *testing.T) {
	resetState()
	st.saveConsensusState(types.ClientId(1), types.NewHeight(10), []byte("consensus-state"))

	got := QueryConsensusState(types.ClientId(1), types.NewHeight(10))
	if got != "0x636f6e73656e7375732d7374617465" {
		t.Errorf("GetConsensusState: got %q want hex consensus-state", got)
	}
}

func TestQueryConsensusStateUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()
	st.saveConsensusState(types.ClientId(1), types.NewHeight(10), []byte("consensus-state"))

	if got := QueryConsensusState(types.ClientId(999), types.NewHeight(10)); got != "" {
		t.Errorf("QueryConsensusState unknown client: got %q want empty", got)
	}
	if got := QueryConsensusState(types.ClientId(1), types.NewHeight(999)); got != "" {
		t.Errorf("QueryConsensusState unknown height: got %q want empty", got)
	}
}

func TestCreateClientStoresInitialClientAndConsensusState(cur realm, t *testing.T) {
	resetState()
	st.clientRegistry[mockType] = &mockClient{chainId: "union-1", height: types.NewHeight(100)}

	clientId := CreateClient(cross(cur), types.MsgCreateClient{
		ClientType:          mockType,
		ClientStateBytes:    []byte("client-state"),
		ConsensusStateBytes: []byte("consensus-state"),
	})

	if got := QueryClientState(clientId); got != "0x636c69656e742d7374617465" {
		t.Errorf("GetClientState: got %q want hex client-state", got)
	}
	if got := QueryConsensusState(clientId, types.NewHeight(100)); got != "0x636f6e73656e7375732d7374617465" {
		t.Errorf("GetConsensusState: got %q want hex consensus-state", got)
	}
}

// Union requires client updates to run only against active clients; this locks
// the guard before the light client implementation mutates local state.
func TestUpdateClientRejectsInactiveClient(cur realm, t *testing.T) {
	resetState()
	clientId := types.ClientId(1)
	client := &mockClient{chainId: "union-1", height: types.NewHeight(100), status: types.StatusFrozen}
	st.clientRegistry[mockType] = client
	st.clientTypes[clientId] = mockType
	st.saveClientState(clientId, []byte("client-state"))
	st.saveConsensusState(clientId, types.NewHeight(100), []byte("consensus-state"))

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		UpdateClient(cur, types.MsgUpdateClient{
			ClientId:      clientId,
			ClientMessage: []byte("update"),
		})
	})
	if client.height != types.NewHeight(100) {
		t.Fatalf("inactive UpdateClient must not call light client: got height %s", client.height)
	}
}

// --- State: ID generation ---

func TestGenerateIdsSequential(cur realm, t *testing.T) {
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

func TestSaveAndGetConnection(cur realm, t *testing.T) {
	resetState()
	conn := types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 types.ClientId(1),
		CounterpartyClientId:     types.ClientId(2),
		CounterpartyConnectionId: types.ConnectionId(99),
	}
	id := st.generateConnectionId()
	st.saveConnection(id, conn)

	got := st.getConnection(id)
	if got.State != types.ConnectionStateOpen {
		t.Errorf("state: got %v want Open", got.State)
	}
	if got.ClientId != types.ClientId(1) {
		t.Errorf("clientId: got %v want 1", got.ClientId)
	}

	want := hexString(mustEncodeABI(conn.EncodeABI()))
	if got := QueryConnection(id); got != want {
		t.Errorf("QueryConnection: got %q want %q", got, want)
	}
}

func TestGetConnectionNotFoundPanics(cur realm, t *testing.T) {
	resetState()
	mustPanic(t, func() { st.getConnection(types.ConnectionId(999)) })
}

func TestQueryConnectionUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	got := QueryConnection(types.ConnectionId(999))
	if got != "" {
		t.Errorf("QueryConnection: got %q want empty", got)
	}
}

func TestConnectionStateSaved(cur realm, t *testing.T) {
	resetState()
	id := st.generateConnectionId()
	st.saveConnection(id, types.Connection{State: types.ConnectionStateInit})
	st.saveConnection(id, types.Connection{State: types.ConnectionStateOpen})
	if st.getConnection(id).State != types.ConnectionStateOpen {
		t.Error("connection state must reflect latest save")
	}
}

// ConnectionOpenInit must not create local connection state for a client id that
// has not been registered.
func TestConnectionOpenInitRejectsUnknownClient(cur realm, t *testing.T) {
	resetState()

	uassert.AbortsContains(t, cur, "client not found", func(cur realm) {
		ConnectionOpenInit(cur, types.MsgConnectionOpenInit{
			ClientId:             types.ClientId(404),
			CounterpartyClientId: types.ClientId(99),
		})
	})
	if len(st.connections) != 0 {
		t.Fatal("ConnectionOpenInit must not save a connection for an unknown client")
	}
}

// ConnectionOpenInit is a proof-bearing handshake root, so the selected local
// client must already be active before the connection is saved.
func TestConnectionOpenInitRejectsInactiveClient(cur realm, t *testing.T) {
	resetState()
	clientId := types.ClientId(1)
	st.clientRegistry[mockType] = &mockClient{chainId: "union-1", height: types.NewHeight(100), status: types.StatusExpired}
	st.clientTypes[clientId] = mockType

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		ConnectionOpenInit(cur, types.MsgConnectionOpenInit{
			ClientId:             clientId,
			CounterpartyClientId: types.ClientId(99),
		})
	})
	if len(st.connections) != 0 {
		t.Fatal("ConnectionOpenInit must not save a connection for an inactive client")
	}
}

// --- State: channel ---

func TestSaveAndGetChannel(cur realm, t *testing.T) {
	resetState()
	ch := types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          types.ConnectionId(1),
		CounterpartyChannelId: types.ChannelId(99),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}
	id := st.generateChannelId()
	st.saveChannel(id, ch)

	got := st.getChannel(id)
	if got.State != types.ChannelStateOpen {
		t.Errorf("state: got %v want Open", got.State)
	}
	if got.Version != "ics20-1" {
		t.Errorf("version: got %v want ics20-1", got.Version)
	}

	want := hexString(mustEncodeABI(ch.EncodeABI()))
	if got := QueryChannel(id); got != want {
		t.Errorf("QueryChannel: got %q want %q", got, want)
	}
}

func TestGetChannelNotFoundPanics(cur realm, t *testing.T) {
	resetState()
	mustPanic(t, func() { st.getChannel(types.ChannelId(999)) })
}

func TestQueryChannelUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	got := QueryChannel(types.ChannelId(999))
	if got != "" {
		t.Errorf("QueryChannel: got %q want empty", got)
	}
}

// --- State: packet commitment ---

func TestPacketCommitmentLifecycle(cur realm, t *testing.T) {
	resetState()
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("data"), TimeoutTimestamp: 1000}
	st.commitPacket(p)
	if _, ok := st.batchPackets[types.MustCommit(types.PacketCommitmentPath(p))]; !ok {
		t.Fatal("commitPacket must mirror at packet commitment path")
	}
	st.deletePacketCommitment(p)
	if _, ok := st.batchPackets[types.MustCommit(types.PacketCommitmentPath(p))]; ok {
		t.Fatal("deletePacketCommitment must clear packet commitment path")
	}
}

func TestAcknowledgementDoesNotPanic(cur realm, t *testing.T) {
	resetState()
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	st.commitAcknowledgement(p, []byte("ack"))
}

func TestPacketSendCommitsPacket(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)

	packet := PacketSend(cross(cur), channelId, 100, []byte("data"))

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

func TestPacketSendRejectsNonOwner(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	st.channelOwners[channelId] = types.Bytes("g1notchannelowner")

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		PacketSend(cur, channelId, 100, []byte("data"))
	})
}

func TestPacketSendRejectsAddressAsPortId(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	// Port registered with address (old behavior) must be rejected when caller's
	// PkgPath is compared instead.
	st.channelOwners[channelId] = types.Bytes(oldAddressPort)

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		PacketSend(cur, channelId, 100, []byte("data"))
	})
}

// Source packet commitments need a non-zero timestamp timeout; otherwise the
// timeout invariant cannot be enforced on the counterparty.
func TestPacketSendRejectsZeroTimeoutTimestamp(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)

	uassert.AbortsContains(t, cur, "packet timeout", func(cur realm) {
		PacketSend(cur, channelId, 0, []byte("data"))
	})
}

// PacketSend must reject a second identical source commitment instead of
// silently overwriting the existing commitment.
func TestPacketSendRejectsDuplicateCommitment(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	PacketSend(cross(cur), channelId, 100, []byte("data"))

	uassert.AbortsContains(t, cur, "packet commitment", func(cur realm) {
		PacketSend(cur, channelId, 100, []byte("data"))
	})
}

func TestBatchSendReturnsUnionPacketCommitment(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}

	got := BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	want := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	if got != want {
		t.Fatal("BatchSend must return Union packet batch commitment")
	}
	if got := QueryBatchPackets(want); got != types.COMMITMENT_MAGIC.String() {
		t.Errorf("GetBatchPackets: got %s want %s", got, types.COMMITMENT_MAGIC)
	}
	if v, ok := st.batchPackets[types.BatchPacketsPath(want)]; !ok || v != types.COMMITMENT_MAGIC {
		t.Errorf("batch packet mirror at path: ok=%v value=%s want %s", ok, v, types.COMMITMENT_MAGIC)
	}
	if _, ok := st.batchPackets[want]; ok {
		t.Error("batch packet mirror must not be keyed by raw batch hash")
	}
}

func TestBatchSendPerPacketMirrorKeyedByPath(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}

	BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	for _, packet := range []types.Packet{p1, p2} {
		path := types.MustCommit(types.PacketCommitmentPath(packet))
		got, ok := st.batchPackets[path]
		if !ok {
			t.Fatal("BatchSend must mirror per-packet commitment at the packet commitment path")
		}
		if got != types.COMMITMENT_MAGIC {
			t.Fatalf("per-packet mirror: got %s want %s", got, types.COMMITMENT_MAGIC)
		}
		if _, ok := st.batchPackets[types.MustCommit(types.CommitPacket(packet))]; ok {
			t.Fatal("BatchSend must not mirror per-packet commitment at the raw packet hash")
		}
	}
}

func TestQueryBatchPacketsUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	var batchHash types.H256
	got := QueryBatchPackets(batchHash)
	if got != "" {
		t.Errorf("QueryBatchPackets: got %q want empty", got)
	}
}

func TestQueryCommitmentAtPathReturnsBatchValue(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}

	batchHash := BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})

	if got := QueryCommitmentAtPath(types.BatchPacketsPath(batchHash)); got != types.COMMITMENT_MAGIC.String() {
		t.Errorf("QueryCommitmentAtPath(batch path): got %s want %s", got, types.COMMITMENT_MAGIC)
	}
	for _, packet := range []types.Packet{p1, p2} {
		if got := QueryCommitmentAtPath(types.MustCommit(types.PacketCommitmentPath(packet))); got != types.COMMITMENT_MAGIC.String() {
			t.Errorf("QueryCommitmentAtPath(per-packet path): got %s want %s", got, types.COMMITMENT_MAGIC)
		}
	}
}

func TestQueryCommitmentAtPathUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	var path types.H256
	if got := QueryCommitmentAtPath(path); got != "" {
		t.Errorf("QueryCommitmentAtPath: got %q want empty", got)
	}
}

func TestBatchSendRejectsEmptyPacketList(cur realm, t *testing.T) {
	resetState()
	uassert.AbortsContains(t, cur, "not enough packets", func(cur realm) {
		BatchSend(cur, types.MsgBatchSend{})
	})
}

func TestBatchSendRejectsNonOwner(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	st.channelOwners[channelId] = types.Bytes("gno.land/r/not-channel-owner")
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		BatchSend(cur, types.MsgBatchSend{Packets: []types.Packet{packet}})
	})
}

func TestBatchAcksReturnsUnionPacketCommitment(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	st.commitAcknowledgement(p1, []byte("ack-a"))
	st.commitAcknowledgement(p2, []byte("ack-b"))

	got := BatchAcks(cross(cur), types.MsgBatchAcks{
		Packets: []types.Packet{p1, p2},
		Acks:    [][]byte{[]byte("ack-a"), []byte("ack-b")},
	})
	want := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	if got != want {
		t.Fatal("BatchAcks must return Union packet batch commitment")
	}
	wantAck := types.CommitAcks([][]byte{[]byte("ack-a"), []byte("ack-b")})
	if got := QueryBatchReceipts(want); got != wantAck.String() {
		t.Errorf("GetBatchReceipts: got %s want %s", got, wantAck)
	}
	if v, ok := st.batchReceipts[types.BatchReceiptsPath(want)]; !ok || v != wantAck {
		t.Errorf("batch receipt mirror at path: ok=%v value=%s want %s", ok, v, wantAck)
	}
	if _, ok := st.batchReceipts[want]; ok {
		t.Error("batch receipt mirror must not be keyed by raw batch hash")
	}
}

func TestQueryBatchReceiptsUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	var batchHash types.H256
	got := QueryBatchReceipts(batchHash)
	if got != "" {
		t.Errorf("QueryBatchReceipts: got %q want empty", got)
	}
}

func TestQueryReceiptAtPathReturnsBatchValue(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	st.commitAcknowledgement(p1, []byte("ack-a"))
	st.commitAcknowledgement(p2, []byte("ack-b"))

	batchHash := BatchAcks(cross(cur), types.MsgBatchAcks{
		Packets: []types.Packet{p1, p2},
		Acks:    [][]byte{[]byte("ack-a"), []byte("ack-b")},
	})
	wantAck := types.CommitAcks([][]byte{[]byte("ack-a"), []byte("ack-b")})

	if got := QueryReceiptAtPath(types.BatchReceiptsPath(batchHash)); got != wantAck.String() {
		t.Errorf("QueryReceiptAtPath(batch path): got %s want %s", got, wantAck)
	}
}

func TestQueryReceiptAtPathUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetState()

	var path types.H256
	if got := QueryReceiptAtPath(path); got != "" {
		t.Errorf("QueryReceiptAtPath: got %q want empty", got)
	}
}

func TestBatchAcksRejectsAckCountMismatch(cur realm, t *testing.T) {
	resetState()
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	uassert.AbortsContains(t, cur, "acknowledgement count mismatch", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{p}, Acks: [][]byte{}})
	})
}

func TestBatchAcksRejectsNonOwner(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	st.channelOwners[channelId] = types.Bytes("gno.land/r/not-channel-owner")
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{packet}, Acks: [][]byte{[]byte("ack")}})
	})
}

func TestBatchAcksRejectsPacketsWithoutReceipt(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet receipt not found", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{packet}, Acks: [][]byte{[]byte("ack")}})
	})
	if st.hasAcknowledgement(packet) {
		t.Fatal("BatchAcks must not commit acknowledgement for an unreceived packet")
	}
}

func TestBatchAcksRejectsMismatchedCommittedAck(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}

	st.commitAcknowledgement(packet, []byte("first-ack"))

	uassert.AbortsContains(t, cur, "acknowledgement commitment mismatch", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{packet}, Acks: [][]byte{[]byte("second-ack")}})
	})
}

func TestPacketReceiptLifecycle(cur realm, t *testing.T) {
	resetState()
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if st.hasPacketReceipt(p) {
		t.Fatal("receipt must not exist before set")
	}
	st.setPacketReceipt(p)
	if !st.hasPacketReceipt(p) {
		t.Fatal("receipt must exist after set")
	}
	if _, ok := st.batchReceipts[types.MustCommit(types.PacketAcknowledgementPath(p))]; !ok {
		t.Fatal("setPacketReceipt must mirror at packet acknowledgement path")
	}
	st.deletePacketReceipt(p)
	if st.hasPacketReceipt(p) {
		t.Fatal("receipt must not exist after delete")
	}
	if _, ok := st.batchReceipts[types.MustCommit(types.PacketAcknowledgementPath(p))]; ok {
		t.Fatal("deletePacketReceipt must clear packet acknowledgement path")
	}
}

// Union stores a recv receipt as COMMITMENT_MAGIC; COMMITMENT_MAGIC_ACK is
// reserved for completed source commitments.
func TestPacketReceiptUsesCommitmentMagicSentinel(cur realm, t *testing.T) {
	resetState()
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	st.setPacketReceipt(p)

	path := types.MustCommit(types.PacketAcknowledgementPath(p))
	got := QueryReceiptAtPath(path)
	if got != types.COMMITMENT_MAGIC.String() {
		t.Fatalf("recv receipt sentinel: got %q want %s", got, types.COMMITMENT_MAGIC)
	}
	if st.hasAcknowledgement(p) {
		t.Fatal("received-but-not-acked receipt must not count as an acknowledgement")
	}
}

// --- ensureConnectionOpen ---

func TestEnsureConnectionOpenPanicsOnInit(cur realm, t *testing.T) {
	resetState()
	id := st.generateConnectionId()
	st.saveConnection(id, types.Connection{State: types.ConnectionStateInit})
	mustPanic(t, func() { ensureConnectionOpen(id) })
}

func TestEnsureConnectionOpenSucceeds(cur realm, t *testing.T) {
	resetState()
	id := st.generateConnectionId()
	st.saveConnection(id, types.Connection{State: types.ConnectionStateOpen, ClientId: 1})
	st.clientRegistry[mockType] = &mockClient{}
	st.clientTypes[types.ClientId(1)] = mockType
	conn := ensureConnectionOpen(id)
	if conn.State != types.ConnectionStateOpen {
		t.Error("expected open connection")
	}
}

// --- types.Channel state machine ---

func TestChannelStateTransitions(cur realm, t *testing.T) {
	resetState()
	id := st.generateChannelId()

	st.saveChannel(id, types.Channel{State: types.ChannelStateInit})
	if st.getChannel(id).State != types.ChannelStateInit {
		t.Error("expected Init")
	}
	st.saveChannel(id, types.Channel{State: types.ChannelStateTryOpen})
	if st.getChannel(id).State != types.ChannelStateTryOpen {
		t.Error("expected TryOpen")
	}
	st.saveChannel(id, types.Channel{State: types.ChannelStateOpen})
	if st.getChannel(id).State != types.ChannelStateOpen {
		t.Error("expected Open")
	}
	st.saveChannel(id, types.Channel{State: types.ChannelStateClosed})
	if st.getChannel(id).State != types.ChannelStateClosed {
		t.Error("expected Closed")
	}
}

func TestChannelEventAttrsOmitsCounterpartyChannelIdForOpenInit(cur realm, t *testing.T) {
	attrs := channelEventAttrs(
		ChannelOpenInitEvent,
		types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"),
		types.ChannelId(1),
		types.Channel{
			State:                 types.ChannelStateInit,
			ConnectionId:          types.ConnectionId(2),
			CounterpartyChannelId: types.ChannelId(0),
			CounterpartyPortId:    types.Bytes("counterparty"),
			Version:               "ucs03-zkgm-0",
		},
		types.Connection{
			ClientId:                 types.ClientId(3),
			CounterpartyClientId:     types.ClientId(4),
			CounterpartyConnectionId: types.ConnectionId(5),
		},
	)

	want := []string{
		"port_id", "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"channel_id", "1",
		"counterparty_port_id", "0x636f756e7465727061727479",
		"connection_id", "2",
		"connection_client_id", "3",
		"connection_counterparty_client_id", "4",
		"connection_counterparty_connection_id", "5",
		"version", "ucs03-zkgm-0",
	}
	assertStringSliceEqual(t, attrs, want)
	assertAttrMissing(t, attrs, "counterparty_channel_id")
}

func TestChannelEventAttrsIncludesCounterpartyChannelIdForOtherEvents(cur realm, t *testing.T) {
	events := []string{
		ChannelOpenTryEvent,
		ChannelOpenAckEvent,
		ChannelOpenConfirmEvent,
	}
	for _, eventType := range events {
		attrs := channelEventAttrs(
			eventType,
			types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"),
			types.ChannelId(1),
			types.Channel{
				State:                 types.ChannelStateOpen,
				ConnectionId:          types.ConnectionId(2),
				CounterpartyChannelId: types.ChannelId(7),
				CounterpartyPortId:    types.Bytes("counterparty"),
				Version:               "ucs03-zkgm-0",
			},
			types.Connection{
				ClientId:                 types.ClientId(3),
				CounterpartyClientId:     types.ClientId(4),
				CounterpartyConnectionId: types.ConnectionId(5),
			},
		)

		assertAttrEqual(t, attrs, "counterparty_channel_id", "7")
		assertStringSliceEqual(t, attrs, []string{
			"port_id", "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
			"channel_id", "1",
			"counterparty_port_id", "0x636f756e7465727061727479",
			"counterparty_channel_id", "7",
			"connection_id", "2",
			"connection_client_id", "3",
			"connection_counterparty_client_id", "4",
			"connection_counterparty_connection_id", "5",
			"version", "ucs03-zkgm-0",
		})
	}
}

// --- Port / channel ownership ---

func TestGetAppByPortIdPanicsWhenMissing(cur realm, t *testing.T) {
	resetState()
	mustPanic(t, func() {
		st.getAppByPortId(types.Bytes("g1missing"))
	})
}

func TestGetChannelOwnerPanicsWhenMissing(cur realm, t *testing.T) {
	resetState()
	mustPanic(t, func() {
		st.getChannelOwner(types.ChannelId(999))
	})
}

func TestRegisterClientRejectsUnauthorizedCaller(cur realm, t *testing.T) {
	resetState()
	oldAdmin := admin
	admin = "gno1authorized"
	defer func() { admin = oldAdmin }()

	uassert.AbortsContains(t, cur, "caller not authorized to register client", func(cur realm) {
		RegisterClient(cur, types.ClientType("cometbls"), &mockClient{})
	})
	if HasClient(types.ClientType("cometbls")) {
		t.Fatal("unauthorized RegisterClient must not reserve the client type")
	}
}

func TestRegisterClientScopedNamespaceRejectsExternalType(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewCodeRealm(testCorePkgPath))

	uassert.AbortsContains(t, cur, "caller not authorized to register client", func(cur realm) {
		RegisterClient(cur, types.ClientType("gno.land/r/other/mytype"), &mockClient{})
	})
}

func TestRegisterClientScopedNamespaceRejectsExactCallerPath(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewCodeRealm(testCorePkgPath))

	uassert.AbortsContains(t, cur, "caller not authorized to register client", func(cur realm) {
		RegisterClient(cur, types.ClientType(testCorePkgPath), &mockClient{})
	})
}

func TestRegisterClientScopedNamespaceRejectsSuffixedPath(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewCodeRealm(testCorePkgPath))

	uassert.AbortsContains(t, cur, "caller not authorized to register client", func(cur realm) {
		RegisterClient(cur, types.ClientType(testCorePkgPath+"suffix/x"), &mockClient{})
	})
}

func TestRegisterAppRejectsPortSquatting(cur realm, t *testing.T) {
	resetState()
	oldAdmin := admin
	admin = "gno1authorized"
	defer func() { admin = oldAdmin }()
	portId := types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm")

	uassert.AbortsContains(t, cur, "caller not authorized to register port", func(cur realm) {
		RegisterAppForPort(cur, portId, &mockApp{})
	})
	if HasApp(portId) {
		t.Fatal("unauthorized RegisterApp must not reserve a foreign port")
	}
}

func TestRegisterAppUsesCallerPackagePath(cur realm, t *testing.T) {
	resetState()

	RegisterApp(cross(cur), &mockApp{})
	if !HasApp([]byte(testCorePkgPath)) {
		t.Fatal("RegisterApp must register the caller package path as the port id")
	}
}

func TestRegisterAppRejectsDuplicateRegistration(cur realm, t *testing.T) {
	resetState()

	RegisterApp(cross(cur), &mockApp{})
	uassert.AbortsContains(t, cur, "port already registered", func(cur realm) {
		RegisterApp(cross(cur), &mockApp{})
	})
}

// --- Integration: packet send lifecycle ---

func TestPacketRecvSyncAckWritten(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{
			Packets: []types.Packet{packet},
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

func TestPacketRecvBatchUsesUnionBatchCommitment(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	client := st.clientRegistry[mockType].(*mockClient)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}
	proof := types.Bytes("batch-proof")

	PacketRecv(cross(cur), types.MsgPacketRecv{
		Packets:     []types.Packet{p1, p2},
		RelayerMsgs: [][]byte{[]byte("relay-a"), []byte("relay-b")},
		Proof:       proof,
		ProofHeight: 10,
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	batchHash := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	batchPath := types.BatchPacketsPath(batchHash)
	if string(client.membershipKeys[0]) != string(batchPath[:]) {
		t.Fatal("PacketRecv must verify Union batch packets path")
	}
	if string(client.membershipValues[0]) != string(types.COMMITMENT_MAGIC[:]) {
		t.Fatal("PacketRecv must verify commitment magic for batch packet membership")
	}
	if client.membershipHeights[0] != types.NewHeight(10) || string(client.membershipProofs[0]) != string(proof) {
		t.Fatal("PacketRecv must pass batch proof height and bytes through")
	}
	if len(app.recvPackets) != 2 {
		t.Fatalf("OnRecvPacket calls: got %d want 2", len(app.recvPackets))
	}
	if !st.hasPacketReceipt(p1) || !st.hasPacketReceipt(p2) {
		t.Fatal("PacketRecv must set receipt for every batch packet")
	}
}

func TestPacketRecvBatchRejectsDifferentDestinationChannel(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	otherChannelId := st.generateChannelId()
	st.saveChannel(otherChannelId, types.Channel{State: types.ChannelStateOpen})
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: otherChannelId, Data: types.Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "batch must use the same channel", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{p1, p2}})
	})
}

func TestPacketRecvSyncEmptyAckRejected(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(cur, types.PacketStatusSuccess, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "sync ack cannot be empty", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}})
	})
}

// --- Async acknowledgement ---

func TestPacketRecvAsyncDefersAck(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(cur, types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}})
	})

	if !st.hasPacketReceipt(packet) {
		t.Fatal("async recv must still set packet receipt")
	}
	if st.hasAcknowledgement(packet) {
		t.Fatal("async recv must not commit acknowledgement")
	}
}

func TestWriteAcknowledgementCommitsAsyncAck(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(cur, types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
		Packet:          packet,
		Acknowledgement: []byte("async-ack"),
	})

	if !st.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must commit acknowledgement")
	}
}

func TestWriteAcknowledgementRejectsNonOwner(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(cur, types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	st.channelOwners[channelId] = types.Bytes("g1notchannelowner")

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsAddressAsPortId(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(cur, types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	// Port registered with address (old behavior) must be rejected.
	st.channelOwners[channelId] = types.Bytes(oldAddressPort)

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsEmptyAck(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	st.setPacketReceipt(packet)

	uassert.AbortsContains(t, cur, "acknowledgement cannot be empty", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte{},
		})
	})
	if st.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must not commit an empty acknowledgement")
	}
}

func TestWriteAcknowledgementRejectsAlreadyAcked(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}

	st.setPacketReceipt(packet)
	st.commitAcknowledgement(packet, []byte("ack"))

	uassert.AbortsContains(t, cur, "acknowledgement already written", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsPacketWithoutReceipt(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet receipt not found", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("forged-ack"),
		})
	})
	if st.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must not commit acknowledgement for an unreceived packet")
	}
}

// Async WriteAcknowledgement should only accept the "received but not acked"
// sentinel, not the completed source-side sentinel.
func TestWriteAcknowledgementRejectsCompletedSentinelReceipt(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}
	st.saveBatchReceipts(types.MustCommit(types.CommitPacket(packet)), types.COMMITMENT_MAGIC_ACK)

	uassert.AbortsContains(t, cur, "packet receipt", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestPacketRecvReceiptDupRejected(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})

	if len(app.recvPackets) != 1 {
		t.Fatalf("duplicate recv must not call app again: got %d calls", len(app.recvPackets))
	}
}

func TestIntentPacketRecvSetsReceiptAndCommitsAck(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, cur, func(cur realm) {
		IntentPacketRecv(cur, types.MsgIntentPacketRecv{
			Packets:             []types.Packet{packet},
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
	if !st.hasAcknowledgement(packet) {
		t.Fatal("IntentPacketRecv must write an acknowledgement")
	}
	if st.acknowledgementHash(packet) != types.CommitAcks([][]byte{{0x02}}) {
		t.Fatal("IntentPacketRecv must commit the intent acknowledgement")
	}
}

func TestIntentPacketRecvRejectsNonIntentAppBeforeReceipt(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	st.ports[portKey(portId)] = &mockNonIntentApp{}
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "intent receive not supported", func(cur realm) {
		IntentPacketRecv(cur, types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})
	})

	if st.hasPacketReceipt(packet) {
		t.Fatal("IntentPacketRecv must reject non-intent app before writing receipt")
	}
	if st.hasAcknowledgement(packet) {
		t.Fatal("IntentPacketRecv must reject non-intent app before writing acknowledgement")
	}
}

func TestIntentPacketRecvBlocksLaterProvenPacketRecv(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})
	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})

	if len(app.recvPackets) != 0 {
		t.Fatalf("intent recv receipt must suppress later proven PacketRecv: got %d recv calls", len(app.recvPackets))
	}
	if !st.hasAcknowledgement(packet) {
		t.Fatal("intent PacketRecv must write the packet acknowledgement")
	}
	if st.acknowledgementHash(packet) != types.CommitAcks([][]byte{{0x02}}) {
		t.Fatal("intent acknowledgement must remain committed")
	}
}

func TestIntentPacketRecvDuplicateSkippedByReceipt(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})
	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})

	if len(app.intentPackets) != 1 {
		t.Fatalf("duplicate intent recv must not call app again: got %d calls", len(app.intentPackets))
	}
}

func TestPacketAcknowledgementRoundtrip(cur realm, t *testing.T) {
	resetState()
	portId, connId, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}
	st.commitPacket(packet)
	st.channelOwners[packet.DestinationChannelId] = portId
	st.saveChannel(packet.DestinationChannelId, types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: packet.SourceChannelId,
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	})

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{packet},
		Acknowledgements: [][]byte{{0x01}},
	})

	if len(app.ackPackets) != 1 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 1", len(app.ackPackets))
	}
	if st.hasPacketCommitment(packet) {
		t.Fatal("acknowledgement must delete source packet commitment")
	}
}

// A source ack proves completion by marking the source commitment with
// COMMITMENT_MAGIC_ACK, which also makes duplicate ack delivery a no-op.
func TestPacketAcknowledgementMarksSourceCommitmentCompleted(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}
	st.commitPacket(packet)

	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{packet},
		Acknowledgements: [][]byte{{0x01}},
	})

	path := types.MustCommit(types.PacketCommitmentPath(packet))
	if got := QueryCommitmentAtPath(path); got != types.COMMITMENT_MAGIC_ACK.String() {
		t.Fatalf("source commitment after ack: got %q want %s", got, types.COMMITMENT_MAGIC_ACK)
	}
	if len(app.ackPackets) != 1 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 1", len(app.ackPackets))
	}

	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{packet},
		Acknowledgements: [][]byte{{0x01}},
	})
	if len(app.ackPackets) != 1 {
		t.Fatalf("duplicate ack must be a no-op: got %d calls", len(app.ackPackets))
	}
}

func TestPacketAcknowledgementBatchUsesUnionBatchReceipts(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	client := st.clientRegistry[mockType].(*mockClient)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	st.commitPacket(p1)
	st.commitPacket(p2)
	acks := [][]byte{{0x01}, {0x02}}
	proof := types.Bytes("ack-proof")

	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{p1, p2},
		Acknowledgements: acks,
		Proof:            proof,
		ProofHeight:      10,
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	batchHash := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	receiptPath := types.BatchReceiptsPath(batchHash)
	if string(client.membershipKeys[0]) != string(receiptPath[:]) {
		t.Fatal("PacketAcknowledgement must verify Union batch receipts path")
	}
	ackValue := types.CommitAcks(acks)
	if string(client.membershipValues[0]) != string(ackValue[:]) {
		t.Fatal("PacketAcknowledgement must verify Union batch ack value")
	}
	if client.membershipHeights[0] != types.NewHeight(10) || string(client.membershipProofs[0]) != string(proof) {
		t.Fatal("PacketAcknowledgement must pass batch proof height and bytes through")
	}
	if len(app.ackPackets) != 2 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 2", len(app.ackPackets))
	}
	if st.hasPacketCommitment(p1) || st.hasPacketCommitment(p2) {
		t.Fatal("PacketAcknowledgement must delete every batch packet commitment")
	}
}

func TestPacketAcknowledgementDeletesBatchCommitment(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	acks := [][]byte{{0x01}, {0x02}}

	batchHash := BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	if got := QueryBatchPackets(batchHash); got != types.COMMITMENT_MAGIC.String() {
		t.Fatalf("batch commitment before ack: got %q want %s", got, types.COMMITMENT_MAGIC)
	}

	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{p1, p2},
		Acknowledgements: acks,
		ProofHeight:      10,
	})

	if got := QueryBatchPackets(batchHash); got != "" {
		t.Fatalf("batch commitment after ack: got %q want empty", got)
	}
}

func TestPacketAcknowledgementBatchRejectsDifferentSourceChannel(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	otherChannelId := st.generateChannelId()
	st.saveChannel(otherChannelId, types.Channel{State: types.ChannelStateOpen})
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: otherChannelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	st.commitPacket(p1)
	st.commitPacket(p2)

	uassert.AbortsContains(t, cur, "batch must use the same channel", func(cur realm) {
		PacketAcknowledgement(cur, types.MsgPacketAcknowledgement{
			Packets:          []types.Packet{p1, p2},
			Acknowledgements: [][]byte{{0x01}, {0x02}},
		})
	})
}

func TestPacketTimeoutReceiptPath(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	st.commitPacket(packet)
	client := st.clientRegistry[mockType].(*mockClient)

	PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})

	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("non-membership calls: got %d want 1", len(client.nonMembershipKeys))
	}
	got := string(client.nonMembershipKeys[0])
	receiptPath := types.BatchReceiptsPath(types.MustCommit(types.CommitPacket(packet)))
	want := string(receiptPath[:])
	if got != want {
		t.Fatal("PacketTimeout must verify Union batch receipt non-membership")
	}
	if st.hasPacketCommitment(packet) {
		t.Fatal("timeout must delete source packet commitment")
	}
}

// A timeout proof completes the same source commitment state machine as ack,
// using COMMITMENT_MAGIC_ACK instead of deleting the commitment path.
func TestPacketTimeoutMarksSourceCommitmentCompleted(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	st.commitPacket(packet)

	PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})

	path := types.MustCommit(types.PacketCommitmentPath(packet))
	if got := QueryCommitmentAtPath(path); got != types.COMMITMENT_MAGIC_ACK.String() {
		t.Fatalf("source commitment after timeout: got %q want %s", got, types.COMMITMENT_MAGIC_ACK)
	}
	if len(app.timeoutPackets) != 1 {
		t.Fatalf("OnTimeoutPacket calls: got %d want 1", len(app.timeoutPackets))
	}

	PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	if len(app.timeoutPackets) != 1 {
		t.Fatalf("duplicate timeout must be a no-op: got %d calls", len(app.timeoutPackets))
	}
}

func TestPacketTimeoutIsNoOpWhenCommitmentAbsent(cur realm, t *testing.T) {
	resetState()
	packet := types.Packet{SourceChannelId: 1, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	uassert.NotAborts(t, cur, func(cur realm) {
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
	})
}

func TestPacketTimeoutRejectsInactiveClientBeforeNonMembership(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	st.commitPacket(packet)
	client := st.clientRegistry[mockType].(*mockClient)
	client.status = types.StatusFrozen

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
	})

	if len(client.nonMembershipKeys) != 0 {
		t.Fatalf("non-membership calls: got %d want 0", len(client.nonMembershipKeys))
	}
	if !st.hasPacketCommitment(packet) {
		t.Fatal("inactive client must not delete packet commitment")
	}
}

func TestVerifyClientMembershipVerifiesUnionPathValue(cur realm, t *testing.T) {
	resetState()
	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	st.clientRegistry[mockType] = client
	st.clientTypes[types.ClientId(4)] = mockType

	path := types.Bytes("clients/7/consensusStates/11")
	value := types.Bytes("consensus-state")
	proof := types.Bytes("membership-proof")
	VerifyClientMembership(cross(cur), types.ClientId(4), types.NewHeight(10), proof, path, value)

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipClientIds[0] != types.ClientId(4) || client.membershipHeights[0] != types.NewHeight(10) {
		t.Fatal("VerifyClientMembership must pass client id and proof height through")
	}
	if string(client.membershipProofs[0]) != string(proof) ||
		string(client.membershipKeys[0]) != string(path) ||
		string(client.membershipValues[0]) != string(value) {
		t.Fatal("VerifyClientMembership must pass proof path and value through")
	}
}

func TestVerifyClientMembershipRejectsInactiveClientBeforeMembership(cur realm, t *testing.T) {
	resetState()
	client := &mockClient{chainId: "union-1", status: types.StatusExpired}
	st.clientRegistry[mockType] = client
	st.clientTypes[types.ClientId(4)] = mockType

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		VerifyClientMembership(cur, types.ClientId(4), types.NewHeight(10), types.Bytes("proof"), types.Bytes("path"), types.Bytes("value"))
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
}

// Handler-level guard: PacketRecv must reject an inactive client before it
// verifies the batch membership proof or touches receipt/app state.
func TestPacketRecvRejectsInactiveClient(cur realm, t *testing.T) {
	resetState()
	portId, _, channelId := setupOpenChannel(t)
	app := st.ports[portKey(portId)].(*mockApp)
	client := st.clientRegistry[mockType].(*mockClient)
	client.status = types.StatusFrozen
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, Proof: types.Bytes("proof"), ProofHeight: 10})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if len(app.recvPackets) != 0 {
		t.Fatalf("OnRecvPacket calls: got %d want 0", len(app.recvPackets))
	}
	if st.hasPacketReceipt(packet) {
		t.Fatal("inactive client must not set packet receipt")
	}
	if st.hasAcknowledgement(packet) {
		t.Fatal("inactive client must not commit acknowledgement")
	}
}

// Handler-level guard: ChannelOpenTry must reject an inactive client before it
// verifies the counterparty membership proof or persists the channel.
func TestChannelOpenTryRejectsInactiveClient(cur realm, t *testing.T) {
	resetState()
	portId, connId, _ := setupOpenChannel(t)
	client := st.clientRegistry[mockType].(*mockClient)
	client.status = types.StatusExpired
	channelsBefore := len(st.channelOwners)
	channel := types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: types.ChannelId(99),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		ChannelOpenTry(cur, types.MsgChannelOpenTry{PortId: portId, Channel: channel, CounterpartyVersion: "ics20-1", ProofInit: types.Bytes("proof"), ProofHeight: 10})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if len(st.channelOwners) != channelsBefore {
		t.Fatal("inactive client must not persist a new channel")
	}
}

func TestChannelOpenAckRejectsWrongState(cur realm, t *testing.T) {
	resetState()
	channelId := st.generateChannelId()
	st.saveChannel(channelId, types.Channel{State: types.ChannelStateOpen})

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		ChannelOpenAck(cur, types.MsgChannelOpenAck{
			ChannelId:             channelId,
			CounterpartyVersion:   "ics20-1",
			CounterpartyChannelId: types.ChannelId(99),
		})
	})
}

func TestChannelOpenConfirmRejectsWrongState(cur realm, t *testing.T) {
	resetState()
	channelId := st.generateChannelId()
	st.saveChannel(channelId, types.Channel{State: types.ChannelStateOpen})

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		ChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{
			ChannelId: channelId,
		})
	})
}

func TestGetClientStatusDelegatesToClient(cur realm, t *testing.T) {
	resetState()
	st.clientRegistry[mockType] = &mockClient{chainId: "union-1", status: types.StatusFrozen}
	st.clientTypes[types.ClientId(4)] = mockType

	if got := GetClientStatus(types.ClientId(4)); got != types.StatusFrozen {
		t.Fatalf("GetClientStatus: got %d want %d", got, types.StatusFrozen)
	}
}

func TestGetClientStatusReturnsUnknownForMissingClient(cur realm, t *testing.T) {
	resetState()

	if got := GetClientStatus(types.ClientId(5)); got != types.StatusUnknown {
		t.Fatalf("GetClientStatus missing: got %d want %d", got, types.StatusUnknown)
	}
}

// --- ForceUpdateClient ---

func TestForceUpdateClientUpdatesStateAndReturnsHeight(cur realm, t *testing.T) {
	resetState()
	adminAddr := testutils.TestAddress("admin")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	admin = adminAddr
	mc := &mockForceClient{}
	st.clientRegistry[mockType] = mc
	clientId := CreateClient(cross(cur), types.MsgCreateClient{
		ClientType:          mockType,
		ClientStateBytes:    []byte("cs-old"),
		ConsensusStateBytes: []byte("cons-old"),
	})

	height := ForceUpdateClient(cross(cur), types.MsgForceUpdateClient{
		ClientId:            clientId,
		ClientStateBytes:    []byte("cs-new"),
		ConsensusStateBytes: []byte("cons-new"),
	})

	if height != types.NewHeight(1) {
		t.Fatalf("ForceUpdateClient height: got %v want 1", height)
	}
	if got := QueryClientState(clientId); got != "0x"+hexEncodeString("cs-new") {
		t.Fatalf("client state not updated: got %q", got)
	}
	if got := QueryConsensusState(clientId, height); got != "0x"+hexEncodeString("cons-new") {
		t.Fatalf("consensus state not updated: got %q", got)
	}
}

func TestForceUpdateClientPanicsWhenClientDoesNotSupportForceUpdate(cur realm, t *testing.T) {
	resetState()
	adminAddr := testutils.TestAddress("admin")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	admin = adminAddr
	st.clientRegistry[mockType] = &mockClient{}
	clientId := CreateClient(cross(cur), types.MsgCreateClient{
		ClientType:          mockType,
		ClientStateBytes:    []byte("cs"),
		ConsensusStateBytes: []byte("cons"),
	})

	uassert.AbortsContains(t, cur, "client does not support ForceUpdateClient", func(cur realm) {
		ForceUpdateClient(cur, types.MsgForceUpdateClient{
			ClientId:            clientId,
			ClientStateBytes:    []byte("cs-new"),
			ConsensusStateBytes: []byte("cons-new"),
		})
	})
}

func TestForceUpdateClientPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetState()
	admin = "gno1authorized"
	defer func() { admin = "" }()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceUpdateClient(cur, types.MsgForceUpdateClient{
			ClientId:            types.ClientId(0),
			ClientStateBytes:    []byte("cs"),
			ConsensusStateBytes: []byte("cons"),
		})
	})
}

func hexEncodeString(s string) string {
	const hextable = "0123456789abcdef"
	dst := make([]byte, len(s)*2)
	for i, c := range []byte(s) {
		dst[i*2] = hextable[c>>4]
		dst[i*2+1] = hextable[c&0x0f]
	}
	return string(dst)
}

// --- Admin ---

func TestGetAdminReflectsCurrentAdmin(cur realm, t *testing.T) {
	old := admin
	defer func() { admin = old }()
	sentinel := testutils.TestAddress("admin-sentinel")
	admin = sentinel
	if got := GetAdmin(); got != sentinel {
		t.Errorf("GetAdmin: got %v want %v", got, sentinel)
	}
}

func TestSetAdminTransfersRights(cur realm, t *testing.T) {
	old := admin
	defer func() { admin = old }()
	oldAdmin := testutils.TestAddress("old-admin")
	newAdmin := testutils.TestAddress("new-admin")
	admin = oldAdmin

	testing.SetRealm(testing.NewUserRealm(oldAdmin))
	SetAdmin(cross(cur), newAdmin)

	if GetAdmin() != newAdmin {
		t.Fatalf("admin not transferred; got %v want %v", GetAdmin(), newAdmin)
	}

	// After transfer admin=newAdmin; closure caller != newAdmin → rejected.
	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		requireAdmin(cur, "set admin")
	})
	if GetAdmin() != newAdmin {
		t.Error("rejected call must not revert the transfer")
	}
}

func TestSetAdminRejectsNonAdmin(cur realm, t *testing.T) {
	old := admin
	defer func() { admin = old }()
	adminAddr := testutils.TestAddress("authorized-admin")
	admin = adminAddr

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		requireAdmin(cur, "set admin")
	})
	if admin != adminAddr {
		t.Error("rejected call must not change the admin")
	}
}

// --- Integration: channel close ---

func TestUnionChannelCloseDatagramsUnsupported(cur realm, t *testing.T) {
	resetState()
	uassert.AbortsContains(t, cur, "Union types.MsgChannelCloseInit has no channel id", func(cur realm) {
		ChannelCloseInit(cur, types.MsgChannelCloseInit{})
	})
	uassert.AbortsContains(t, cur, "Union types.MsgChannelCloseConfirm has no channel id", func(cur realm) {
		ChannelCloseConfirm(cur, types.MsgChannelCloseConfirm{})
	})
}
