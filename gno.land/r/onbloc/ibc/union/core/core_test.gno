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
	mockClientImplPath              = "gno.land/r/onbloc/ibc/union/core/testing/mock-client"
	testCorePkgPath                  = "gno.land/r/onbloc/ibc/union/core"
	oldAddressPort                   = "g1vjt8cj2s6f5w4sly0s2l0vh85k0y8jyz3f8qzss"
)

func resetStore() {
	store = newStore()
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
	return store.addClient(mockType, testutils.TestAddress("mock-client-creator"), mockClientImplPath, mc)
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

// Union reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/client/ibc.rs#L127-L190
func TestGetClientStateReturnsStoredBytes(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	c.saveState([]byte("client-state"))

	got := QueryClientState(c.id)
	if got != "0x636c69656e742d7374617465" {
		t.Errorf("GetClientState: got %q want hex client-state", got)
	}
	if got := GetClientState(c.id); got != "0x636c69656e742d7374617465" {
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

// Union reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/client/ibc.rs#L30-L62
func TestGetRegisteredClientTypeReturnsRegisteredType(cur realm, t *testing.T) {
	resetStore()
	addMockClient(&mockClient{})

	if got := GetRegisteredClientType(mockType); got != mockClientImplPath {
		t.Errorf("GetRegisteredClientType: got %q want %q", got, mockClientImplPath)
	}
	if !HasClient(mockType) {
		t.Fatal("HasClient: got false want true")
	}
	if got := GetRegisteredClientType(types.ClientType("missing")); got != "" {
		t.Errorf("GetRegisteredClientType missing: got %q want empty", got)
	}
	if HasClient(types.ClientType("missing")) {
		t.Fatal("HasClient missing: got true want false")
	}
}

// Union reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/client/ibc.rs#L127-L190
func TestGetClientImplReturnsIdentifier(cur realm, t *testing.T) {
	resetStore()
	clientId := registerMockClient(&mockClient{})

	if got := GetClientImpl(clientId); got != mockClientImplPath {
		t.Fatalf("GetClientImpl: got %q want %q", got, mockClientImplPath)
	}
	if got := GetClientImpl(types.ClientId(999)); got != "" {
		t.Fatalf("GetClientImpl unknown: got %q want empty", got)
	}
}

func TestGetLatestHeightAndTimestampAtHeight(cur realm, t *testing.T) {
	resetStore()
	clientId := registerMockClient(&mockClient{
		height:    types.NewHeight(42),
		timestamp: types.Timestamp(12345),
	})

	if got := GetLatestHeight(clientId); got != 42 {
		t.Fatalf("GetLatestHeight: got %d want 42", got)
	}
	if got := GetTimestampAtHeight(clientId, 42); got != types.Timestamp(12345) {
		t.Fatalf("GetTimestampAtHeight: got %d want 12345", got)
	}
	if got := GetLatestHeight(types.ClientId(999)); got != 0 {
		t.Fatalf("GetLatestHeight unknown: got %d want 0", got)
	}
	if got := GetTimestampAtHeight(types.ClientId(999), 42); got != 0 {
		t.Fatalf("GetTimestampAtHeight unknown: got %d want 0", got)
	}
}

// Union reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/client/ibc.rs#L127-L190
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

// Union reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/client/ibc.rs#L127-L190
func TestGetConsensusStateReturnsStoredBytes(cur realm, t *testing.T) {
	resetStore()
	c := addMockClient(&mockClient{})
	c.saveConsensusState(types.NewHeight(10), []byte("consensus-state"))

	got := QueryConsensusState(c.id, types.NewHeight(10))
	if got != "0x636f6e73656e7375732d7374617465" {
		t.Errorf("GetConsensusState: got %q want hex consensus-state", got)
	}
	if got := GetConsensusState(c.id, 10); got != "0x636f6e73656e7375732d7374617465" {
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

// Union reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L81-L104
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
	if got := GetConnection(id); got.State != types.ConnectionStateOpen {
		t.Errorf("GetConnection state: got %v want Open", got.State)
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

func TestGetConnectionNotFoundPanics(cur realm, t *testing.T) {
	resetStore()
	mustPanic(t, func() { GetConnection(types.ConnectionId(999)) })
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

// Union reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L126-L176
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

func TestGetChannelsReturnsAppChannels(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)

	got := GetChannels(cross(cur), string(portId))
	if len(got) != 1 {
		t.Fatalf("GetChannels: got %v want one channel", got)
	}
	if got[0] != uint32(channelId) {
		t.Fatalf("GetChannels[0]: got %d want %d", got[0], channelId)
	}
	if missing := GetChannels(cross(cur), "missing-port"); len(missing) != 0 {
		t.Fatalf("GetChannels missing: got %v want empty", missing)
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

func TestPacketSendCommitsPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)

	packet := PacketSend(cross(cur), channelId, 100, []byte("data"))

	if packet.SourceChannelId != channelId {
		t.Fatal("PacketSend must preserve source channel")
	}
	if packet.DestinationChannelId != store.getChannel(channelId).CounterpartyChannelId {
		t.Fatal("PacketSend must use channel counterparty as destination")
	}
	if !store.hasPacketCommitment(packet) {
		t.Fatal("PacketSend must commit packet")
	}
}

func TestPacketSendRejectsNonOwner(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	setChannelOwner(channelId, "g1notchannelowner")

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		PacketSend(cur, channelId, 100, []byte("data"))
	})
}

func TestPacketSendRejectsAddressAsPortId(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	// Port registered with address (old behavior) must be rejected when caller's
	// PkgPath is compared instead.
	setChannelOwner(channelId, oldAddressPort)

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		PacketSend(cur, channelId, 100, []byte("data"))
	})
}

func TestBatchSendReturnsUnionPacketCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}

	got := BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	want := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	if got != want {
		t.Fatal("BatchSend must return Union packet batch commitment")
	}
	if got := QueryBatchPackets(channelId, want); got != types.COMMITMENT_MAGIC.String() {
		t.Errorf("GetBatchPackets: got %s want %s", got, types.COMMITMENT_MAGIC)
	}
	if got := GetBatchPackets(want); got != types.COMMITMENT_MAGIC.String() {
		t.Errorf("GetBatchPackets: got %s want %s", got, types.COMMITMENT_MAGIC)
	}
	if rawV, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(types.BatchPacketsPath(want)); !ok || rawV != types.COMMITMENT_MAGIC {
		t.Errorf("batch packet mirror at path: ok=%v value=%s want %s", ok, rawV, types.COMMITMENT_MAGIC)
	}
	if _, ok := store.clientForChannel(channelId).getBatchPacketsAtPath(want); ok {
		t.Error("batch packet mirror must not be keyed by raw batch hash")
	}
}

func TestBatchSendPerPacketMirrorKeyedByPath(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}

	BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	c := store.clientForChannel(channelId)
	for _, packet := range []types.Packet{p1, p2} {
		path := packetCommitmentPath(packet)
		rawV, ok := c.getBatchPacketsAtPath(path)
		if !ok {
			t.Fatal("BatchSend must mirror per-packet commitment at the packet commitment path")
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
	if got := GetBatchPackets(batchHash); got != "" {
		t.Errorf("GetBatchPackets: got %q want empty", got)
	}
}

func TestQueryCommitmentAtPathReturnsBatchValue(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}

	batchHash := BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})

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
		BatchSend(cur, types.MsgBatchSend{})
	})
}

func TestBatchSendRejectsNonOwner(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	setChannelOwner(channelId, "gno.land/r/not-channel-owner")
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		BatchSend(cur, types.MsgBatchSend{Packets: []types.Packet{packet}})
	})
}

func TestBatchAcksReturnsUnionPacketCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.setPacketReceipt(p1)
	store.setPacketReceipt(p2)

	got := BatchAcks(cross(cur), types.MsgBatchAcks{
		Packets: []types.Packet{p1, p2},
		Acks:    [][]byte{[]byte("ack-a"), []byte("ack-b")},
	})
	want := types.MustCommit(types.CommitPackets([]types.Packet{p1, p2}))
	if got != want {
		t.Fatal("BatchAcks must return Union packet batch commitment")
	}
	wantAck := types.CommitAcks([][]byte{[]byte("ack-a"), []byte("ack-b")})
	if got := QueryBatchReceipts(channelId, want); got != wantAck.String() {
		t.Errorf("GetBatchReceipts: got %s want %s", got, wantAck)
	}
	if got := GetBatchReceipts(want); got != wantAck.String() {
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
	if got := GetBatchReceipts(batchHash); got != "" {
		t.Errorf("GetBatchReceipts: got %q want empty", got)
	}
}

func TestQueryReceiptAtPathReturnsBatchValue(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	store.setPacketReceipt(p1)
	store.setPacketReceipt(p2)

	batchHash := BatchAcks(cross(cur), types.MsgBatchAcks{
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

func TestBatchAcksRejectsAckCountMismatch(cur realm, t *testing.T) {
	resetStore()
	p := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	uassert.AbortsContains(t, cur, "acknowledgement count mismatch", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{p}, Acks: [][]byte{}})
	})
}

func TestBatchAcksRejectsNonOwner(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	setChannelOwner(channelId, "gno.land/r/not-channel-owner")
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: 100}

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{packet}, Acks: [][]byte{[]byte("ack")}})
	})
}

func TestBatchAcksRejectsPacketsWithoutReceipt(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet receipt not found", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{packet}, Acks: [][]byte{[]byte("ack")}})
	})
	if store.hasAcknowledgement(packet) {
		t.Fatal("BatchAcks must not commit acknowledgement for an unreceived packet")
	}
}

func TestBatchAcksRejectsAlreadyAckedPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}

	store.setPacketReceipt(packet)
	store.commitAcknowledgement(packet, []byte("first-ack"))

	uassert.AbortsContains(t, cur, "acknowledgement already written", func(cur realm) {
		BatchAcks(cur, types.MsgBatchAcks{Packets: []types.Packet{packet}, Acks: [][]byte{[]byte("second-ack")}})
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
	if _, ok := c.getBatchReceiptsAtPath(packetAcknowledgementPath(p)); !ok {
		t.Fatal("setPacketReceipt must mirror at packet acknowledgement path")
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
		PacketRecv(cur, types.MsgPacketRecv{
			Packets: []types.Packet{packet},
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

func TestPacketRecvBatchRejectsDifferentDestinationChannel(cur realm, t *testing.T) {
	resetStore()
	_, connId, channelId := setupOpenChannel(t)
	otherChannelId := store.nextChannelId()
	store.createChannel(otherChannelId, types.Channel{State: types.ChannelStateOpen, ConnectionId: connId}, nil)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: otherChannelId, Data: types.Bytes("b"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "batch must use the same channel", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{p1, p2}})
	})
}

func TestPacketRecvSyncEmptyAckRejected(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusSuccess, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("transfer"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "sync ack cannot be empty", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}})
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
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}})
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

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
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

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	setChannelOwner(channelId, "g1notchannelowner")

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
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

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	// Port registered with address (old behavior) must be rejected.
	setChannelOwner(channelId, oldAddressPort)

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
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
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
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
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
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
		WriteAcknowledgement(cur, types.MsgWriteAcknowledgement{
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

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})

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

func TestIntentPacketRecvRejectsNonIntentAppBeforeReceipt(cur realm, t *testing.T) {
	resetStore()
	portId, _, channelId := setupOpenChannel(t)
	store.ports[portKey(portId)] = &mockNonIntentApp{}
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("intent"), TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "intent receive not supported", func(cur realm) {
		IntentPacketRecv(cur, types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})
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

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})
	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})

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

	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})
	IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: []types.Packet{packet}})

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

	PacketRecv(cross(cur), types.MsgPacketRecv{Packets: []types.Packet{packet}})
	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{packet},
		Acknowledgements: [][]byte{{0x01}},
	})

	if len(app.ackPackets) != 1 {
		t.Fatalf("OnAcknowledgementPacket calls: got %d want 1", len(app.ackPackets))
	}
	if store.hasPacketCommitment(packet) {
		t.Fatal("acknowledgement must delete source packet commitment")
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
	if store.hasPacketCommitment(p1) || store.hasPacketCommitment(p2) {
		t.Fatal("PacketAcknowledgement must delete every batch packet commitment")
	}
}

func TestPacketAcknowledgementDeletesBatchCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}
	acks := [][]byte{{0x01}, {0x02}}

	batchHash := BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	if got := QueryBatchPackets(channelId, batchHash); got != types.COMMITMENT_MAGIC.String() {
		t.Fatalf("batch commitment before ack: got %q want %s", got, types.COMMITMENT_MAGIC)
	}

	PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{p1, p2},
		Acknowledgements: acks,
		ProofHeight:      10,
	})

	if got := QueryBatchPackets(channelId, batchHash); got != "" {
		t.Fatalf("batch commitment after ack: got %q want empty", got)
	}
}

func TestPacketAcknowledgementBatchRejectsDifferentSourceChannel(cur realm, t *testing.T) {
	resetStore()
	_, connId, channelId := setupOpenChannel(t)
	otherChannelId := store.nextChannelId()
	store.createChannel(otherChannelId, types.Channel{State: types.ChannelStateOpen, ConnectionId: connId}, nil)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes("a"), TimeoutTimestamp: 100}
	p2 := types.Packet{SourceChannelId: otherChannelId, DestinationChannelId: 99, Data: types.Bytes("b"), TimeoutTimestamp: 100}

	// Channel check is validated before commitment check, so commitments are not
	// required for the different-source-channel panic to fire.
	uassert.AbortsContains(t, cur, "batch must use the same channel", func(cur realm) {
		PacketAcknowledgement(cur, types.MsgPacketAcknowledgement{
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
	if store.hasPacketCommitment(packet) {
		t.Fatal("timeout must delete source packet commitment")
	}
}

func TestPacketTimeoutIsNoOpWhenCommitmentAbsent(cur realm, t *testing.T) {
	resetStore()
	packet := types.Packet{SourceChannelId: 1, DestinationChannelId: 99, Data: types.Bytes("transfer"), TimeoutTimestamp: 100}
	uassert.NotAborts(t, cur, func(cur realm) {
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
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
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
	})

	if len(client.nonMembershipKeys) != 0 {
		t.Fatalf("non-membership calls: got %d want 0", len(client.nonMembershipKeys))
	}
	if !store.hasPacketCommitment(packet) {
		t.Fatal("inactive client must not delete packet commitment")
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
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, Proof: types.Bytes("proof"), ProofHeight: 10})
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
	if got := GetStatus(clientId); got != types.StatusFrozen {
		t.Fatalf("GetStatus: got %d want %d", got, types.StatusFrozen)
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
