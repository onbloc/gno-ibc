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

func resetStore() {
	store = newStore()
	admin = packageAddress
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

func setChannelOwner(channelId types.ChannelId, portId string) {
	entry, found := store.getChannelEntry(channelId)
	if !found {
		panic("channel " + channelId.String() + " not found")
	}
	entry.portId = types.Bytes(portId)
}

func addMockClient(mc *mockClient) *client {
	return store.addClient(mockType, testutils.TestAddress("mock-client-creator"), mc)
}

func registerMockClient(mc *mockClient) types.ClientId {
	return addMockClient(mc).id
}

// mockClientFor returns the mock light client object core stored for the client
// that owns channelId, so tests can inspect recorded calls or mutate its status.
func mockClientFor(channelId types.ChannelId) *mockClient {
	return store.clientForChannel(channelId).lightClient.(*mockClient)
}

func addMockConnection(state types.ConnectionState) types.ConnectionId {
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	connectionId := store.nextConnectionId()
	store.saveConnection(connectionId, types.Connection{
		State:                    state,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(99),
	})
	return connectionId
}

func setupOpenChannel(t *testing.T) (types.Bytes, types.ConnectionId, types.ChannelId) {
	t.Helper()
	clientId := addMockClient(&mockClient{chainId: "union-1", height: types.NewHeight(100), status: types.StatusActive}).id

	connId := store.nextConnectionId()
	store.saveConnection(connId, types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(99),
	})

	portId := types.Bytes(testCorePkgPath)
	app := &mockApp{}
	store.ports[portKey(portId)] = app

	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: types.ChannelId(99),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}, portId)
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

func TestGetClientNotFoundReturnsNil(cur realm, t *testing.T) {
	resetStore()
	if store.getClient(types.ClientId(999)) != nil {
		t.Fatal("unknown client must return nil")
	}
}

func TestGetClientStateReturnsStoredBytes(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	c.saveState([]byte("client-state"))

	got := QueryClientState(c.id)
	if got != "0x636c69656e742d7374617465" {
		t.Errorf("GetClientState: got %q want hex client-state", got)
	}
}

func TestQueryClientStateUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	got := QueryClientState(types.ClientId(999))
	if got != "" {
		t.Errorf("QueryClientState: got %q want empty", got)
	}
}

func TestGetClientTypeReturnsRegisteredType(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})

	got := GetClientType(c.id)
	if got != string(mockType) {
		t.Errorf("GetClientType: got %q want %q", got, string(mockType))
	}
}

func TestGetClientTypeUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	got := GetClientType(types.ClientId(999))
	if got != "" {
		t.Errorf("GetClientType: got %q want empty", got)
	}
}

func TestGetConsensusStateReturnsStoredBytes(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	c.saveConsensusState(types.NewHeight(10), []byte("consensus-state"))

	got := QueryConsensusState(c.id, types.NewHeight(10))
	if got != "0x636f6e73656e7375732d7374617465" {
		t.Errorf("GetConsensusState: got %q want hex consensus-state", got)
	}
}

func TestQueryConsensusStateUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	c.saveConsensusState(types.NewHeight(10), []byte("consensus-state"))

	if got := QueryConsensusState(types.ClientId(999), types.NewHeight(10)); got != "" {
		t.Errorf("QueryConsensusState unknown client: got %q want empty", got)
	}
	if got := QueryConsensusState(c.id, types.NewHeight(999)); got != "" {
		t.Errorf("QueryConsensusState unknown height: got %q want empty", got)
	}
}

func TestCreateClientBuildsAndStoresObject(cur realm, t *testing.T) {
	resetStore()
	creatorAddr := testutils.TestAddress("client-creator")
	testing.SetRealm(testing.NewUserRealm(creatorAddr))
	mc := &mockClient{chainId: "union-1", height: types.NewHeight(100)}

	clientId := CreateClient(cross(cur), mockType, mc)

	c := store.getClient(clientId)
	if c == nil {
		t.Fatalf("client not added to store")
	}
	if c.lightClient != mc {
		t.Fatalf("stored client lightClient mismatch")
	}
	if c.creator != creatorAddr {
		t.Fatalf("stored client creator mismatch: got %s want %s", c.creator, creatorAddr)
	}
	if c.typ != mockType {
		t.Fatalf("stored client type mismatch: got %s want %s", c.typ, mockType)
	}
}

// --- State: ID sequences ---

func TestNextIdsSequential(cur realm, t *testing.T) {
	resetStore()
	c1, c2 := addMockClient(&mockClient{}), addMockClient(&mockClient{})
	if c2.id != c1.id+1 {
		t.Errorf("client IDs not sequential: got %v and %v", c1.id, c2.id)
	}
	n1, n2 := store.nextConnectionId(), store.nextConnectionId()
	if n2 != n1+1 {
		t.Errorf("connection IDs not sequential: got %v and %v", n1, n2)
	}
	h1, h2 := store.nextChannelId(), store.nextChannelId()
	if h2 != h1+1 {
		t.Errorf("channel IDs not sequential: got %v and %v", h1, h2)
	}
}

// --- State: connection ---

func TestSaveAndGetConnection(cur realm, t *testing.T) {
	resetStore()
	clientId := registerMockClient(&mockClient{})
	conn := types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(2),
		CounterpartyConnectionId: types.ConnectionId(99),
	}
	id := store.nextConnectionId()
	store.saveConnection(id, conn)

	got, ok := store.getConnection(id)
	if !ok {
		t.Fatal("connection not found")
	}
	if got.State != types.ConnectionStateOpen {
		t.Errorf("state: got %v want Open", got.State)
	}
	if got.ClientId != clientId {
		t.Errorf("clientId: got %v want %v", got.ClientId, clientId)
	}

	want := hexString(mustEncodeABI(conn.EncodeABI()))
	if got := QueryConnection(id); got != want {
		t.Errorf("QueryConnection: got %q want %q", got, want)
	}
}

func TestGetConnectionNotFoundReturnsFalse(cur realm, t *testing.T) {
	resetStore()
	if _, ok := store.getConnection(types.ConnectionId(999)); ok {
		t.Fatal("unknown connection must return false")
	}
}

func TestQueryConnectionUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	got := QueryConnection(types.ConnectionId(999))
	if got != "" {
		t.Errorf("QueryConnection: got %q want empty", got)
	}
}

func TestConnectionStateSaved(cur realm, t *testing.T) {
	resetStore()
	clientId := registerMockClient(&mockClient{})
	id := store.nextConnectionId()
	store.saveConnection(id, types.Connection{State: types.ConnectionStateInit, ClientId: clientId})
	store.saveConnection(id, types.Connection{State: types.ConnectionStateOpen, ClientId: clientId})
	conn, ok := store.getConnection(id)
	if !ok {
		t.Fatal("connection not found")
	}
	if conn.State != types.ConnectionStateOpen {
		t.Error("connection state must reflect latest save")
	}
}

// --- State: channel ---

func TestSaveAndGetChannel(cur realm, t *testing.T) {
	resetStore()
	connectionId := addMockConnection(types.ConnectionStateOpen)
	ch := types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connectionId,
		CounterpartyChannelId: types.ChannelId(99),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}
	id := store.nextChannelId()
	store.createChannel(id, ch, nil)

	got := store.getChannel(id)
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
	resetStore()
	mustPanic(t, func() { store.getChannel(types.ChannelId(999)) })
}

func TestQueryChannelUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	got := QueryChannel(types.ChannelId(999))
	if got != "" {
		t.Errorf("QueryChannel: got %q want empty", got)
	}
}

// --- State: packet commitment ---

func TestPacketCommitmentLifecycle(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("data"), TimeoutTimestamp: 1000}
	c.commitPacket(p)
	if _, ok := c.getBatchPacketsAtPath(packetCommitmentPath(p)); !ok {
		t.Fatal("commitPacket must mirror at packet commitment path")
	}
	c.deletePacketCommitment(p)
	if _, ok := c.getBatchPacketsAtPath(packetCommitmentPath(p)); ok {
		t.Fatal("deletePacketCommitment must clear packet commitment path")
	}
}

func TestAcknowledgementDoesNotPanic(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	c.commitAcknowledgement(p, []byte("ack"))
}

func TestSendPacketCommitsPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)

	data := []byte{0, 1, 2}
	timeout := types.Timestamp(1000000)
	packet := SendPacket(cross(cur), channelId, timeout, data)
	channel := store.getChannel(channelId)

	if packet.SourceChannelId != channelId {
		t.Fatal("SendPacket must preserve source channel")
	}
	if packet.DestinationChannelId != channel.CounterpartyChannelId {
		t.Fatal("SendPacket must use channel counterparty as destination")
	}
	if string(packet.Data) != string(data) {
		t.Fatalf("SendPacket data: got %x want %x", []byte(packet.Data), data)
	}
	if packet.TimeoutHeight != 0 {
		t.Fatalf("SendPacket timeout height: got %s want 0", packet.TimeoutHeight.String())
	}
	if packet.TimeoutTimestamp != timeout {
		t.Fatalf("SendPacket timeout timestamp: got %s want %s", packet.TimeoutTimestamp.String(), timeout.String())
	}

	path := packetCommitmentPath(packet)
	if got, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(path); !ok || got != types.COMMITMENT_MAGIC {
		t.Fatalf("SendPacket commitment at path: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC)
	}
}

func TestSendPacketRejectsZeroTimeout(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)

	uassert.AbortsContains(t, cur, "timeout must be set", func(cur realm) {
		SendPacket(cross(cur), channelId, 0, []byte("data"))
	})
}

func TestSendPacketRejectsMissingChannel(cur realm, t *testing.T) {
	resetStore()
	setupOpenChannel(t)

	uassert.AbortsContains(t, cur, "channel 3 not found", func(cur realm) {
		SendPacket(cross(cur), types.ChannelId(3), 100, []byte("data"))
	})
}

func TestSendPacketRejectsNonOpenChannel(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)

	channel := store.getChannel(channelId)
	channel.State = types.ChannelStateInit
	store.saveChannel(channelId, channel)

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		SendPacket(cross(cur), channelId, 100, []byte("data"))
	})
}

// Gno-specific regression: SendPacket needs an open connection to emit connection attrs.
func TestSendPacketRejectsNonOpenConnection(cur realm, t *testing.T) {
	resetStore()
	_, connId, channelId := setupOpenChannel(t)

	connection, ok := store.getConnection(connId)
	if !ok {
		t.Fatal("setupOpenChannel must create connection")
	}
	connection.State = types.ConnectionStateInit
	store.saveConnection(connId, connection)

	uassert.AbortsContains(t, cur, "invalid connection state", func(cur realm) {
		SendPacket(cross(cur), channelId, 100, []byte("data"))
	})
}

func TestSendPacketRejectsDuplicateCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)

	SendPacket(cross(cur), channelId, 100, []byte("data"))

	uassert.AbortsContains(t, cur, "packet commitment already exists", func(cur realm) {
		SendPacket(cross(cur), channelId, 100, []byte("data"))
	})
}

func TestSendPacketRejectsNonOwner(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	setChannelOwner(channelId, "g1notchannelowner")

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		SendPacket(cross(cur), channelId, 100, []byte("data"))
	})
}

func TestSendPacketRejectsAddressAsPortId(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	// Port registered with address (old behavior) must be rejected when caller's
	// PkgPath is compared instead.
	setChannelOwner(channelId, oldAddressPort)

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		SendPacket(cross(cur), channelId, 100, []byte("data"))
	})
}

func TestBatchSendWritesUnionPacketCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)

	want := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	if got := QueryBatchPackets(channelId, want); got != types.COMMITMENT_MAGIC.String() {
		t.Errorf("GetBatchPackets: got %s want %s", got, types.COMMITMENT_MAGIC)
	}
	if rawV, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(types.BatchPacketsPath(want)); !ok || rawV != types.COMMITMENT_MAGIC {
		t.Errorf("batch packet mirror at path: ok=%v value=%s want %s", ok, rawV, types.COMMITMENT_MAGIC)
	}
	if _, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(want); ok {
		t.Error("batch packet mirror must not be keyed by raw batch hash")
	}
}

func TestBatchSendPreservesPerPacketCommitments(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)

	BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	c := store.clientForChannel(channelId)
	for _, packet := range []types.Packet{p1, p2} {
		path := packetCommitmentPath(packet)
		rawV, ok := c.getBatchPacketsAtPath(path)
		if !ok {
			t.Fatal("BatchSend must preserve per-packet commitment at the packet commitment path")
		}
		if rawV != types.COMMITMENT_MAGIC {
			t.Fatalf("per-packet mirror: got %s want %s", rawV, types.COMMITMENT_MAGIC)
		}
		if _, ok := c.getBatchPacketsAtPath(commitPacketHash(packet)); ok {
			t.Fatal("BatchSend must not mirror per-packet commitment at the raw packet hash")
		}
	}
}

func TestQueryBatchPacketsUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	var batchHash types.H256
	got := QueryBatchPackets(types.ChannelId(0), batchHash)
	if got != "" {
		t.Errorf("QueryBatchPackets: got %q want empty", got)
	}
}

func TestQueryCommitmentAtPathReturnsBatchValue(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)

	batchHash := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})

	if got := QueryCommitmentAtPath(channelId, types.BatchPacketsPath(batchHash)); got != types.COMMITMENT_MAGIC.String() {
		t.Errorf("QueryCommitmentAtPath(batch path): got %s want %s", got, types.COMMITMENT_MAGIC)
	}
	for _, packet := range []types.Packet{p1, p2} {
		if got := QueryCommitmentAtPath(channelId, types.MustCommit(types.PacketCommitmentPath(packet))); got != types.COMMITMENT_MAGIC.String() {
			t.Errorf("QueryCommitmentAtPath(per-packet path): got %s want %s", got, types.COMMITMENT_MAGIC)
		}
	}
}

func TestQueryCommitmentAtPathUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	var path types.H256
	if got := QueryCommitmentAtPath(types.ChannelId(0), path); got != "" {
		t.Errorf("QueryCommitmentAtPath: got %q want empty", got)
	}
}

func TestBatchSendRejectsEmptyPacketList(cur realm, t *testing.T) {
	resetStore()
	uassert.AbortsContains(t, cur, "not enough packets", func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{})
	})
}

func TestBatchSendRejectsSinglePacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	store.commitPacket(packet)

	uassert.AbortsContains(t, cur, "not enough packets", func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{packet}})
	})
}

func TestBatchSendAllowsNonOwnerForCommittedPackets(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	setChannelOwner(channelId, "gno.land/r/not-channel-owner")
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)

	uassert.NotAborts(t, cur, func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	})
}

func TestBatchSendRejectsDifferentSourceChannel(cur realm, t *testing.T) {
	resetStore()
	_, connId, channelId := setupOpenChannel(t)
	otherChannelId := store.nextChannelId()
	store.createChannel(otherChannelId, types.Channel{State: types.ChannelStateOpen, ConnectionId: connId}, nil)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: otherChannelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)

	uassert.AbortsContains(t, cur, "batch must use the same channel", func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	})
}

func TestBatchSendRejectsAlreadyAcknowledgedPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)
	if err := store.clientForChannel(channelId).markPacketAcknowledged(p2); err != nil {
		t.Fatal(err)
	}

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	})
}

func TestBatchAcksWritesUnionPacketCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitAcknowledgement(p1, []byte("ack-a"))
	store.commitAcknowledgement(p2, []byte("ack-b"))

	want := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	BatchAcks(cross(cur), types.MsgBatchAcks{
		Packets: []types.Packet{p1, p2},
		Acks:    [][]byte{[]byte("ack-a"), []byte("ack-b")},
	})
	wantAck := types.CommitAcks([][]byte{[]byte("ack-a"), []byte("ack-b")})
	if got := QueryBatchReceipts(channelId, want); got != wantAck.String() {
		t.Errorf("GetBatchReceipts: got %s want %s", got, wantAck)
	}
	if rawV, ok := store.clientForChannel(channelId).getBatchReceiptsAtPath(types.BatchReceiptsPath(want)); !ok || rawV != wantAck {
		t.Errorf("batch receipt mirror at path: ok=%v value=%s want %s", ok, rawV, wantAck)
	}
	if _, ok := store.clientForChannel(channelId).getBatchReceiptsAtPath(want); ok {
		t.Error("batch receipt mirror must not be keyed by raw batch hash")
	}
}

func TestQueryBatchReceiptsUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	var batchHash types.H256
	got := QueryBatchReceipts(types.ChannelId(0), batchHash)
	if got != "" {
		t.Errorf("QueryBatchReceipts: got %q want empty", got)
	}
}

func TestQueryReceiptAtPathReturnsBatchValue(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitAcknowledgement(p1, []byte("ack-a"))
	store.commitAcknowledgement(p2, []byte("ack-b"))

	batchHash := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	BatchAcks(cross(cur), types.MsgBatchAcks{
		Packets: []types.Packet{p1, p2},
		Acks:    [][]byte{[]byte("ack-a"), []byte("ack-b")},
	})
	wantAck := types.CommitAcks([][]byte{[]byte("ack-a"), []byte("ack-b")})

	if got := QueryReceiptAtPath(channelId, types.BatchReceiptsPath(batchHash)); got != wantAck.String() {
		t.Errorf("QueryReceiptAtPath(batch path): got %s want %s", got, wantAck)
	}
}

func TestQueryReceiptAtPathUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	var path types.H256
	if got := QueryReceiptAtPath(types.ChannelId(0), path); got != "" {
		t.Errorf("QueryReceiptAtPath: got %q want empty", got)
	}
}

func TestBatchAcksAllowsAckCountMismatchLikeUnion(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitAcknowledgement(p1, []byte("ack-a"))
	store.commitAcknowledgement(p2, []byte("ack-b"))

	batchHash := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	BatchAcks(cross(cur), types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("ack-a")}})
	want := types.CommitAcks([][]byte{[]byte("ack-a")})
	if got := QueryReceiptAtPath(channelId, types.BatchReceiptsPath(batchHash)); got != want.String() {
		t.Errorf("QueryReceiptAtPath(batch path): got %s want %s", got, want)
	}
}

func TestBatchAcksRejectsSinglePacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "not enough packets", func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{Packets: []types.Packet{packet}, Acks: [][]byte{[]byte("ack")}})
	})
}

func TestBatchAcksAllowsNonOwnerLikeUnion(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	setChannelOwner(channelId, "gno.land/r/not-channel-owner")
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitAcknowledgement(p1, []byte("ack-a"))
	store.commitAcknowledgement(p2, []byte("ack-b"))

	uassert.NotAborts(t, cur, func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("ack-a"), []byte("ack-b")}})
	})
}

func TestBatchAcksRejectsPacketsWithoutReceipt(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("ack-a"), []byte("ack-b")}})
	})
	if store.hasAcknowledgement(p1) || store.hasAcknowledgement(p2) {
		t.Fatal("BatchAcks must not commit acknowledgement for an unreceived packet")
	}
}

func TestBatchAcksRejectsAlreadyAckedPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}

	store.commitAcknowledgement(p1, []byte("first-ack"))
	store.commitAcknowledgement(p2, []byte("second-ack"))

	uassert.AbortsContains(t, cur, "acknowledgement mismatch", func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("tampered-ack"), []byte("second-ack")}})
	})
}

func TestRestrictedPacketEntrypointsRejectNonAdmin(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	admin = testutils.TestAddress("non-admin-sentinel")
	defer func() { admin = oldAdmin }()

	uassert.AbortsContains(t, cur, "caller not authorized to packet recv", func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{})
	})
	uassert.AbortsContains(t, cur, "caller not authorized to intent packet recv", func(cur realm) {
		IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{})
	})
	uassert.AbortsContains(t, cur, "caller not authorized to packet acknowledgement", func(cur realm) {
		PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{})
	})
	uassert.AbortsContains(t, cur, "caller not authorized to packet timeout", func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{})
	})
	uassert.AbortsContains(t, cur, "caller not authorized to batch send", func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{})
	})
	uassert.AbortsContains(t, cur, "caller not authorized to batch acks", func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{})
	})
}

func TestPacketReceiptLifecycle(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	if c.hasPacketReceipt(p) {
		t.Fatal("receipt must not exist before set")
	}
	c.setPacketReceipt(p)
	if !c.hasPacketReceipt(p) {
		t.Fatal("receipt must exist after set")
	}
	if got, ok := c.getBatchReceiptsAtPath(packetAcknowledgementPath(p)); !ok || got != types.COMMITMENT_MAGIC {
		t.Fatalf("setPacketReceipt at packet acknowledgement path: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC)
	}
	if c.hasAcknowledgement(p) {
		t.Fatal("receipt marker must not count as acknowledgement")
	}
	c.deletePacketReceipt(p)
	if c.hasPacketReceipt(p) {
		t.Fatal("receipt must not exist after delete")
	}
	if _, ok := c.getBatchReceiptsAtPath(packetAcknowledgementPath(p)); ok {
		t.Fatal("deletePacketReceipt must clear packet acknowledgement path")
	}
}

// --- ensureConnectionOpen ---

func TestEnsureConnectionOpenPanicsOnInit(cur realm, t *testing.T) {
	resetStore()
	clientId := registerMockClient(&mockClient{})
	id := store.nextConnectionId()
	store.saveConnection(id, types.Connection{State: types.ConnectionStateInit, ClientId: clientId})
	mustPanic(t, func() { ensureConnectionOpen(id) })
}

func TestEnsureConnectionOpenSucceeds(cur realm, t *testing.T) {
	resetStore()
	clientId := registerMockClient(&mockClient{})
	id := store.nextConnectionId()
	store.saveConnection(id, types.Connection{State: types.ConnectionStateOpen, ClientId: clientId})
	conn := ensureConnectionOpen(id)
	if conn.State != types.ConnectionStateOpen {
		t.Error("expected open connection")
	}
}

// --- types.Channel state machine ---

func TestChannelStateTransitions(cur realm, t *testing.T) {
	resetStore()
	connectionId := addMockConnection(types.ConnectionStateOpen)
	id := store.nextChannelId()

	store.createChannel(id, types.Channel{State: types.ChannelStateInit, ConnectionId: connectionId}, nil)
	if store.getChannel(id).State != types.ChannelStateInit {
		t.Error("expected Init")
	}
	store.saveChannel(id, types.Channel{State: types.ChannelStateTryOpen, ConnectionId: connectionId})
	if store.getChannel(id).State != types.ChannelStateTryOpen {
		t.Error("expected TryOpen")
	}
	store.saveChannel(id, types.Channel{State: types.ChannelStateOpen, ConnectionId: connectionId})
	if store.getChannel(id).State != types.ChannelStateOpen {
		t.Error("expected Open")
	}
	store.saveChannel(id, types.Channel{State: types.ChannelStateClosed, ConnectionId: connectionId})
	if store.getChannel(id).State != types.ChannelStateClosed {
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
	resetStore()
	mustPanic(t, func() {
		store.getAppByPortId(types.Bytes("g1missing"))
	})
}

func TestGetChannelOwnerPanicsWhenMissing(cur realm, t *testing.T) {
	resetStore()
	mustPanic(t, func() {
		store.getChannelOwner(types.ChannelId(999))
	})
}

func TestRegisterAppRejectsPortSquatting(cur realm, t *testing.T) {
	resetStore()
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
	resetStore()

	RegisterApp(cross(cur), &mockApp{})
	if !HasApp([]byte(testCorePkgPath)) {
		t.Fatal("RegisterApp must register the caller package path as the port id")
	}
}

func TestRegisterAppRejectsDuplicateRegistration(cur realm, t *testing.T) {
	resetStore()

	RegisterApp(cross(cur), &mockApp{})
	uassert.AbortsContains(t, cur, "port already registered", func(cur realm) {
		RegisterApp(cross(cur), &mockApp{})
	})
}

// --- Integration: packet send lifecycle ---

func TestPacketRecvSyncAckWritten(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{
			Packets:     []types.Packet{packet},
			RelayerMsgs: [][]byte{nil},
		})
	})

	if len(app.recvPackets) != 1 {
		t.Fatalf("OnRecvPacket calls: got %d want 1", len(app.recvPackets))
	}
	if !store.hasPacketReceipt(packet) {
		t.Fatal("PacketRecv must set packet receipt")
	}
	if !store.hasAcknowledgement(packet) {
		t.Fatal("PacketRecv must commit sync acknowledgement")
	}
}

func TestPacketRecvBatchUsesUnionBatchCommitment(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	client := mockClientFor(channelId)
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
	if !store.hasPacketReceipt(p1) || !store.hasPacketReceipt(p2) {
		t.Fatal("PacketRecv must set receipt for every batch packet")
	}
}

func TestPacketRecvStopsAtRelayerMsgLength(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{
		Packets:     []types.Packet{p1, p2},
		RelayerMsgs: [][]byte{[]byte("relay-a")},
	})

	if len(app.recvPackets) != 1 {
		t.Fatalf("OnRecvPacket calls: got %d want 1", len(app.recvPackets))
	}
	if !store.hasPacketReceipt(p1) {
		t.Fatal("PacketRecv must set receipt for the zipped packet")
	}
	if store.hasPacketReceipt(p2) {
		t.Fatal("PacketRecv must not process packets beyond relayer msg length")
	}
}

func TestPacketRecvIgnoresMsgRelayerForAppCallback(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	forged := testutils.TestAddress("forged-relayer")
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{
		Packets:     []types.Packet{packet},
		RelayerMsgs: [][]byte{[]byte("relay-msg")},
		Relayer:     forged,
	})

	if len(app.recvRelayers) != 1 {
		t.Fatalf("OnRecvPacket relayer calls: got %d want 1", len(app.recvRelayers))
	}
	if app.recvRelayers[0] == forged {
		t.Fatal("PacketRecv must not trust Msg.Relayer for app callback attribution")
	}
}

func TestPacketRecvBatchRejectsDifferentDestinationChannel(cur realm, t *testing.T) {
	resetStore()
	_, connId, channelId := setupOpenChannel(t)
	otherChannelId := store.nextChannelId()
	store.createChannel(otherChannelId, types.Channel{State: types.ChannelStateOpen, ConnectionId: connId}, nil)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: otherChannelId, Data: types.Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "batch must use the same channel", func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{p1, p2}, RelayerMsgs: [][]byte{nil, nil}})
	})
}

func TestPacketRecvSyncEmptyAckRejected(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusSuccess, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "sync ack cannot be empty", func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	})
}

// --- Async acknowledgement ---

func TestPacketRecvAsyncDefersAck(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	})

	if !store.hasPacketReceipt(packet) {
		t.Fatal("async recv must still set packet receipt")
	}
	if store.hasAcknowledgement(packet) {
		t.Fatal("async recv must not commit acknowledgement")
	}
}

func TestWriteAcknowledgementCommitsAsyncAck(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
		Packet:          packet,
		Acknowledgement: []byte("async-ack"),
	})

	if !store.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must commit acknowledgement")
	}
}

func TestWriteAcknowledgementRejectsNonOwner(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	setChannelOwner(channelId, "g1notchannelowner")

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsAddressAsPortId(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	// Port registered with address (old behavior) must be rejected.
	setChannelOwner(channelId, oldAddressPort)

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsEmptyAck(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	store.setPacketReceipt(packet)

	uassert.AbortsContains(t, cur, "acknowledgement cannot be empty", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte{},
		})
	})
	if store.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must not commit an empty acknowledgement")
	}
}

func TestWriteAcknowledgementRejectsAlreadyAcked(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}

	store.setPacketReceipt(packet)
	store.commitAcknowledgement(packet, []byte("ack"))

	uassert.AbortsContains(t, cur, "acknowledgement already written", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("async-ack"),
		})
	})
}

func TestWriteAcknowledgementRejectsPacketWithoutReceipt(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet receipt not found", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte("forged-ack"),
		})
	})
	if store.hasAcknowledgement(packet) {
		t.Fatal("WriteAcknowledgement must not commit acknowledgement for an unreceived packet")
	}
}

func TestPacketRecvReceiptDupRejected(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})

	if len(app.recvPackets) != 1 {
		t.Fatalf("duplicate recv must not call app again: got %d calls", len(app.recvPackets))
	}
}

func TestIntentPacketRecvSetsReceiptAndCommitsAck(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.NotAborts(t, cur, func(cur realm) {
		IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{
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
	if !store.hasPacketReceipt(packet) {
		t.Fatal("IntentPacketRecv must set packet receipt")
	}
	if !store.hasAcknowledgement(packet) {
		t.Fatal("IntentPacketRecv must write an acknowledgement")
	}
	if store.acknowledgementHash(packet) != types.CommitAcks([][]byte{{0x02}}) {
		t.Fatal("IntentPacketRecv must commit the intent acknowledgement")
	}
}

func TestIntentPacketRecvStopsAtMarketMakerMsgLength(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent-a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent-b"), TimeoutTimestamp: testFutureTimeoutNanos}

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{
		Packets:             []types.Packet{p1, p2},
		MarketMakerMessages: [][]byte{[]byte("maker-a")},
	})

	if len(app.intentPackets) != 1 {
		t.Fatalf("OnIntentRecvPacket calls: got %d want 1", len(app.intentPackets))
	}
	if !store.hasPacketReceipt(p1) {
		t.Fatal("IntentPacketRecv must set receipt for the zipped packet")
	}
	if store.hasPacketReceipt(p2) {
		t.Fatal("IntentPacketRecv must not process packets beyond maker msg length")
	}
}

func TestIntentPacketRecvIgnoresMsgMarketMakerForAppCallback(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	forged := testutils.TestAddress("forged-maker")
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{
		Packets:             []types.Packet{packet},
		MarketMakerMessages: [][]byte{[]byte("maker-msg")},
		MarketMaker:         forged,
	})

	if len(app.intentMakers) != 1 {
		t.Fatalf("OnIntentRecvPacket maker calls: got %d want 1", len(app.intentMakers))
	}
	if app.intentMakers[0] == forged {
		t.Fatal("IntentPacketRecv must not trust Msg.MarketMaker for app callback attribution")
	}
}

func TestIntentPacketRecvRejectsNonIntentAppBeforeReceipt(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	store.ports[portKey(portId)] = &mockNonIntentApp{}
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "intent receive not supported", func(cur realm) {
		IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}, MarketMakerMessages: [][]byte{nil}})
	})

	if store.hasPacketReceipt(packet) {
		t.Fatal("IntentPacketRecv must reject non-intent app before writing receipt")
	}
	if store.hasAcknowledgement(packet) {
		t.Fatal("IntentPacketRecv must reject non-intent app before writing acknowledgement")
	}
}

func TestIntentPacketRecvBlocksLaterProvenPacketRecv(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}, MarketMakerMessages: [][]byte{nil}})
	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})

	if len(app.recvPackets) != 0 {
		t.Fatalf("intent recv receipt must suppress later proven PacketRecv: got %d recv calls", len(app.recvPackets))
	}
	if !store.hasAcknowledgement(packet) {
		t.Fatal("intent PacketRecv must write the packet acknowledgement")
	}
	if store.acknowledgementHash(packet) != types.CommitAcks([][]byte{{0x02}}) {
		t.Fatal("intent acknowledgement must remain committed")
	}
}

func TestIntentPacketRecvDuplicateSkippedByReceipt(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}, MarketMakerMessages: [][]byte{nil}})
	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}, MarketMakerMessages: [][]byte{nil}})

	if len(app.intentPackets) != 1 {
		t.Fatalf("duplicate intent recv must not call app again: got %d calls", len(app.intentPackets))
	}
}

func TestPacketAcknowledgementRoundtrip(cur realm, t *testing.T) {
	resetStore()
	portId, connId, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}
	store.commitPacket(packet)
	store.createChannel(packet.DestinationChannelId, types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: packet.SourceChannelId,
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}, portId)

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{packet},
		Acknowledgements: [][]byte{{0x01}},
	})

	if len(app.ackPackets) != 1 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 1", len(app.ackPackets))
	}
	if got, ok := store.clientForChannel(packet.SourceChannelId).getBatchPacketsAtPath(packetCommitmentPath(packet)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("acknowledgement marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
}

func TestPacketAcknowledgementBatchUsesUnionBatchReceipts(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	client := mockClientFor(channelId)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)
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
	if got, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(packetCommitmentPath(p1)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("p1 acknowledgement marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
	if got, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(packetCommitmentPath(p2)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("p2 acknowledgement marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
}

func TestPacketAcknowledgementAllowsAckCountMismatchLikeUnion(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)
	store.commitPacket(p2)

	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{p1, p2},
		Acknowledgements: [][]byte{{0x01}},
		Proof:            []byte("ack-proof"),
		ProofHeight:      10,
	})

	if len(app.ackPackets) != 1 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 1", len(app.ackPackets))
	}
	if got, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(packetCommitmentPath(p1)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("p1 acknowledgement marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
	if got, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(packetCommitmentPath(p2)); !ok || got != types.COMMITMENT_MAGIC {
		t.Fatalf("p2 acknowledgement marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC)
	}
}

func TestPacketAcknowledgementPreservesBatchCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	acks := [][]byte{{0x01}, {0x02}}
	store.commitPacket(p1)
	store.commitPacket(p2)

	batchHash := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	if got := QueryBatchPackets(channelId, batchHash); got != types.COMMITMENT_MAGIC.String() {
		t.Fatalf("batch commitment before ack: got %q want %s", got, types.COMMITMENT_MAGIC)
	}

	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{p1, p2},
		Acknowledgements: acks,
		ProofHeight:      10,
	})

	if got := QueryBatchPackets(channelId, batchHash); got != types.COMMITMENT_MAGIC.String() {
		t.Fatalf("batch commitment after ack: got %q want %s", got, types.COMMITMENT_MAGIC)
	}
	if got, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(packetCommitmentPath(p1)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("p1 acknowledgement marker after ack: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
	if got, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(packetCommitmentPath(p2)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("p2 acknowledgement marker after ack: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
}

func TestPacketAcknowledgementBatchRejectsDifferentSourceChannel(cur realm, t *testing.T) {
	resetStore()
	_, connId, channelId := setupOpenChannel(t)
	otherChannelId := store.nextChannelId()
	store.createChannel(otherChannelId, types.Channel{State: types.ChannelStateOpen, ConnectionId: connId}, nil)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: otherChannelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.commitPacket(p1)

	uassert.AbortsContains(t, cur, "batch must use the same channel", func(cur realm) {
		PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
			Packets:          []types.Packet{p1, p2},
			Acknowledgements: [][]byte{{0x01}, {0x02}},
		})
	})
}

func TestPacketTimeoutReceiptPath(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	store.commitPacket(packet)
	client := mockClientFor(channelId)

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
	if got, ok := store.clientForChannel(packet.SourceChannelId).getBatchPacketsAtPath(packetCommitmentPath(packet)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("timeout marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
}

func TestPacketTimeoutRejectsUnsentPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	})
}

func TestPacketTimeoutRejectsInactiveClientBeforeNonMembership(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	store.commitPacket(packet)
	client := mockClientFor(channelId)
	client.status = types.StatusFrozen

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	})

	if len(client.nonMembershipKeys) != 0 {
		t.Fatalf("non-membership calls: got %d want 0", len(client.nonMembershipKeys))
	}
	if !store.hasPacketCommitment(packet) {
		t.Fatal("inactive client must not delete packet commitment")
	}
}

func TestPacketTimeoutIgnoresMsgRelayerForAppCallback(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	msgRelayer := testutils.TestAddress("msg-timeout-relayer")
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	store.commitPacket(packet)

	PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet, Relayer: msgRelayer})

	if len(app.timeoutRelayers) != 1 {
		t.Fatalf("OnTimeoutPacket relayers: got %d want 1", len(app.timeoutRelayers))
	}
	if app.timeoutRelayers[0] == msgRelayer {
		t.Fatal("PacketTimeout must ignore Msg.Relayer for app callback attribution")
	}
}

func TestVerifyClientMembershipVerifiesUnionPathValue(cur realm, t *testing.T) {
	resetStore()
	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)

	path := types.Bytes("clients/7/consensusStates/11")
	value := types.Bytes("consensus-state")
	proof := types.Bytes("membership-proof")
	VerifyClientMembership(cross(cur), clientId, types.NewHeight(10), proof, path, value)

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipHeights[0] != types.NewHeight(10) {
		t.Fatal("VerifyClientMembership must pass proof height through")
	}
	if string(client.membershipProofs[0]) != string(proof) ||
		string(client.membershipKeys[0]) != string(path) ||
		string(client.membershipValues[0]) != string(value) {
		t.Fatal("VerifyClientMembership must pass proof path and value through")
	}
}

func TestVerifyClientMembershipRejectsInactiveClientBeforeMembership(cur realm, t *testing.T) {
	resetStore()
	client := &mockClient{chainId: "union-1", status: types.StatusExpired}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		VerifyClientMembership(cur, clientId, types.NewHeight(10), types.Bytes("proof"), types.Bytes("path"), types.Bytes("value"))
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
}

// Handler-level guard: PacketRecv must reject an inactive client before it
// verifies the batch membership proof or touches receipt/app state.
func TestPacketRecvRejectsInactiveClient(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	client := mockClientFor(channelId)
	client.status = types.StatusFrozen
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}, Proof: types.Bytes("proof"), ProofHeight: 10})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if len(app.recvPackets) != 0 {
		t.Fatalf("OnRecvPacket calls: got %d want 0", len(app.recvPackets))
	}
	if store.hasPacketReceipt(packet) {
		t.Fatal("inactive client must not set packet receipt")
	}
	if store.hasAcknowledgement(packet) {
		t.Fatal("inactive client must not commit acknowledgement")
	}
}

// Handler-level guard: ChannelOpenTry must reject an inactive client before it
// verifies the counterparty membership proof or persists the channel.
func TestChannelOpenTryRejectsInactiveClient(cur realm, t *testing.T) {
	resetStore()
	portId, connId, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.status = types.StatusExpired
	nextChannelId := types.ChannelId(uint32(store.channelSeq) + 1)
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
	if _, found := store.getChannelEntry(nextChannelId); found {
		t.Fatal("inactive client must not persist a new channel")
	}
}

func TestChannelOpenAckRejectsWrongState(cur realm, t *testing.T) {
	resetStore()
	connectionId := addMockConnection(types.ConnectionStateOpen)
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateOpen, ConnectionId: connectionId}, nil)

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		ChannelOpenAck(cur, types.MsgChannelOpenAck{
			ChannelId:             channelId,
			CounterpartyVersion:   "ics20-1",
			CounterpartyChannelId: types.ChannelId(99),
		})
	})
}

func TestChannelOpenConfirmRejectsWrongState(cur realm, t *testing.T) {
	resetStore()
	connectionId := addMockConnection(types.ConnectionStateOpen)
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateOpen, ConnectionId: connectionId}, nil)

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		ChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{
			ChannelId: channelId,
		})
	})
}

func TestGetClientStatusDelegatesToClient(cur realm, t *testing.T) {
	resetStore()
	clientId := registerMockClient(&mockClient{chainId: "union-1", status: types.StatusFrozen})

	if got := GetClientStatus(clientId); got != types.StatusFrozen {
		t.Fatalf("GetClientStatus: got %d want %d", got, types.StatusFrozen)
	}
}

func TestGetClientStatusReturnsUnknownForMissingClient(cur realm, t *testing.T) {
	resetStore()

	if got := GetClientStatus(types.ClientId(5)); got != types.StatusUnknown {
		t.Fatalf("GetClientStatus missing: got %d want %d", got, types.StatusUnknown)
	}
}

// --- ForceUpdateClient ---

func TestForceUpdateClientReplacesObjectAndReturnsHeight(cur realm, t *testing.T) {
	resetStore()
	adminAddr := testutils.TestAddress("admin")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	admin = adminAddr

	clientId := CreateClient(cross(cur), mockType, &mockClient{height: types.NewHeight(0)})

	// The replacement object (built by the caller) reports latest height 1.
	replacement := &mockClient{height: types.NewHeight(1)}
	height := ForceUpdateClient(cross(cur), clientId, replacement)

	if height != types.NewHeight(1) {
		t.Fatalf("ForceUpdateClient height: got %v want 1", height)
	}
	if store.getClient(clientId).lightClient != replacement {
		t.Fatalf("ForceUpdateClient did not replace the stored client object")
	}
}

func TestForceUpdateClientPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	admin = "gno1authorized"
	defer func() { admin = "" }()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceUpdateClient(cur, types.ClientId(0), &mockClient{})
	})
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
	resetStore()
	uassert.AbortsContains(t, cur, "Union types.MsgChannelCloseInit has no channel id", func(cur realm) {
		ChannelCloseInit(cur, types.MsgChannelCloseInit{})
	})
	uassert.AbortsContains(t, cur, "Union types.MsgChannelCloseConfirm has no channel id", func(cur realm) {
		ChannelCloseConfirm(cur, types.MsgChannelCloseConfirm{})
	})
}
