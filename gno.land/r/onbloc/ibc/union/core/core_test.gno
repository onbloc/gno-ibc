package core

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// --- Helpers ---

const (
	mockType        types.ClientType = "mock"
	testCorePkgPath                  = "gno.land/r/onbloc/ibc/union/core"
)

func resetStore(cur realm) {
	store = newStore()
	eventConfig = DefaultEventConfig()
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

func addMockClient(mc *mockClient) *client {
	return store.addClient(store.nextClientId(), mockType, testutils.TestAddress("mock-client-creator"), mc)
}

func registerMockClient(mc *mockClient) types.ClientId {
	return addMockClient(mc).id
}

func addMockConnection(state types.ConnectionState) types.ConnectionId {
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	connectionId := store.nextConnectionId()
	counterpartyConnectionId := types.ConnectionId(0)
	if state == types.ConnectionStateOpen {
		counterpartyConnectionId = types.ConnectionId(99)
	}
	store.saveConnection(connectionId, types.Connection{
		State:                    state,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: counterpartyConnectionId,
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

func TestRenderShowsNextClientID(cur realm, t *testing.T) {
	resetStore(cur)

	cases := []struct {
		name string
		want string
		step func()
	}{
		{"initial", "next client id: 1", func() {}},
		{"after increment", "next client id: 2", func() { store.nextClientId() }},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tc.step()
			if got := Render(""); got != tc.want {
				t.Fatalf("Render: got %q want %q", got, tc.want)
			}
		})
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
	resetStore(cur)
	if store.getClient(types.ClientId(999)) != nil {
		t.Fatal("unknown client must return nil")
	}
}

// --- State: ID sequences ---

func TestNextIdsSequential(cur realm, t *testing.T) {
	resetStore(cur)
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
	resetStore(cur)
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
	resetStore(cur)
	if _, ok := store.getConnection(types.ConnectionId(999)); ok {
		t.Fatal("unknown connection must return false")
	}
}

func TestQueryConnectionUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore(cur)

	got := QueryConnection(types.ConnectionId(999))
	if got != "" {
		t.Errorf("QueryConnection: got %q want empty", got)
	}
}

func TestConnectionStateSaved(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{})
	id := store.nextConnectionId()
	store.saveConnection(id, types.Connection{State: types.ConnectionStateInit, ClientId: clientId})
	store.saveConnection(id, types.Connection{State: types.ConnectionStateOpen, ClientId: clientId, CounterpartyConnectionId: types.ConnectionId(99)})
	conn, ok := store.getConnection(id)
	if !ok {
		t.Fatal("connection not found")
	}
	if conn.State != types.ConnectionStateOpen {
		t.Error("connection state must reflect latest save")
	}
}

// --- State: channel ---

func TestGetChannelNotFoundPanics(cur realm, t *testing.T) {
	resetStore(cur)
	mustPanic(t, func() { store.getChannel(types.ChannelId(999)) })
}

func TestRestrictedPacketEntrypointsRejectNonAdmin(cur realm, t *testing.T) {
	resetStore(cur)

	requireSelectorProtectedForTest(cur, SelectorPacketRecv)
	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{})
	})

	requireSelectorProtectedForTest(cur, SelectorIntentPacketRecv)
	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{})
	})

	requireSelectorProtectedForTest(cur, SelectorPacketAck)
	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{})
	})

	requireSelectorProtectedForTest(cur, SelectorPacketTimeout)
	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{})
	})

	requireSelectorProtectedForTest(cur, SelectorBatchSend)
	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{})
	})

	requireSelectorProtectedForTest(cur, SelectorBatchAcks)
	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{})
	})
}

func TestRestrictedPacketEntrypointsAllowRelayerRealmCallToReachImpl(cur realm, t *testing.T) {
	resetStore(cur)
	oldImpl := currentImpl
	currentImpl = nil
	defer func() {
		currentImpl = oldImpl
	}()

	authorizedRelayer := testutils.TestAddress("authorized-relayer")
	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	access.GrantRole(cross(cur), RelayerRole, authorizedRelayer)
	defer func() {
		testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
		access.RevokeRole(cross(cur), RelayerRole, authorizedRelayer)
	}()

	tests := []struct {
		name   string
		caller address
		run    func(cur realm)
	}{
		{"packet recv", authorizedRelayer, func(cur realm) { PacketRecv(cross(cur), types.MsgPacketRecv{}) }},
		{"intent packet recv", authorizedRelayer, func(cur realm) { IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{}) }},
		{"packet acknowledgement", authorizedRelayer, func(cur realm) { PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{}) }},
		{"packet timeout", authorizedRelayer, func(cur realm) { PacketTimeout(cross(cur), types.MsgPacketTimeout{}) }},
		{"commit membership proof", access.DefaultAdminAddress, func(cur realm) { CommitMembershipProof(cross(cur), types.MsgCommitMembershipProof{}) }},
		{"commit non-membership proof", access.DefaultAdminAddress, func(cur realm) { CommitNonMembershipProof(cross(cur), types.MsgCommitNonMembershipProof{}) }},
		{"batch send", authorizedRelayer, func(cur realm) { BatchSend(cross(cur), types.MsgBatchSend{}) }},
		{"batch acks", authorizedRelayer, func(cur realm) { BatchAcks(cross(cur), types.MsgBatchAcks{}) }},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, "implementation not installed", func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(tc.caller))
				tc.run(cur)
			})
		})
	}
}

// --- types.Channel state machine ---

func TestChannelStateTransitions(cur realm, t *testing.T) {
	resetStore(cur)
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

// --- Port / channel ownership ---

func TestGetAppByPortIdPanicsWhenMissing(cur realm, t *testing.T) {
	resetStore(cur)
	mustPanic(t, func() {
		store.getAppByPortId(types.Bytes("g1missing"))
	})
}

func TestGetChannelOwnerPanicsWhenMissing(cur realm, t *testing.T) {
	resetStore(cur)
	mustPanic(t, func() {
		store.getChannelOwner(types.ChannelId(999))
	})
}

// --- ForceUpdateClient ---

func TestForceUpdateClientPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	requireSelectorProtectedForTest(cur, SelectorForceUpdateClient)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ForceUpdateClient(cross(cur), types.NewMsgForceUpdateClient(types.ClientId(0), nil, nil))
	})
}
