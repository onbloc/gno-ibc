package statelensics23mpt

import (
	"bytes"
	"crypto/keccak256"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/encoding/abi"
	"gno.land/p/onbloc/encoding/rlp"
	ics23mpt "gno.land/p/onbloc/ibc/union/lightclient/state_lens/ics23_mpt"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/p/onbloc/verifier/evm/storage"
	"gno.land/r/onbloc/ibc/union/core"
)

const (
	stateLensTestPortId                  = "gno.land/r/onbloc/ibc/lightclients/state_lens/ics23_mpt"
	mockL1ClientType    types.ClientType = stateLensTestPortId + "/mock-l1"
)

var (
	mockL1Status        types.Status
	wantMembershipCheck bool
	wantClientId        types.ClientId
	wantHeight          types.Height
	wantProof           []byte
	wantKey             []byte
	wantValue           []byte
	stateLensTestApp    = &flowApp{}
)

type mockL1Client struct{}

func (mockL1Client) CreateClient(_ realm, _ types.ClientId, _, _ []byte) string { return "l1" }
func (mockL1Client) UpdateClient(_ realm, _ types.ClientId, _ []byte) types.ConsensusStateUpdate {
	return types.ConsensusStateUpdate{}
}

func (mockL1Client) VerifyMembership(clientId types.ClientId, height types.Height, proof, key, value []byte) {
	if !wantMembershipCheck {
		panic("unexpected membership verification")
	}
	if clientId != wantClientId || height != wantHeight {
		panic("membership target mismatch")
	}
	if !bytes.Equal(proof, wantProof) || !bytes.Equal(key, wantKey) || !bytes.Equal(value, wantValue) {
		panic("membership proof payload mismatch")
	}
}
func (mockL1Client) VerifyNonMembership(_ types.ClientId, _ types.Height, _, _ []byte) {}
func (mockL1Client) GetTimestamp(_ types.ClientId, _ types.Height) types.Timestamp     { return 0 }
func (mockL1Client) GetLatestHeight(_ types.ClientId) types.Height                     { return types.Height{} }
func (mockL1Client) GetStatus(_ types.ClientId) types.Status                           { return mockL1Status }

type flowApp struct {
	recvCount int
}

func (a *flowApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
}

func (a *flowApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _, _ string, _ address) {
}

func (a *flowApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
}
func (a *flowApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address)  {}
func (a *flowApp) OnChannelCloseInit(_ realm, _ types.ChannelId, _ address)    {}
func (a *flowApp) OnChannelCloseConfirm(_ realm, _ types.ChannelId, _ address) {}
func (a *flowApp) OnRecvPacket(cur realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	a.recvCount++
	return core.NewRecvPacketResult(cross(cur), types.PacketStatusSuccess, []byte{0x01})
}

func (a *flowApp) OnIntentRecvPacket(cur realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), types.PacketStatusSuccess, []byte{0x01})
}

func (a *flowApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {
}
func (a *flowApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address) {}

type stateLensFlow struct {
	app                   *flowApp
	l1ClientId            types.ClientId
	l2ClientId            types.ClientId
	lensClientId          types.ClientId
	channelId             types.ChannelId
	counterpartyChannelId types.ChannelId
}

func resetTestState(cur realm) {
	entries = make(map[types.ClientId]*clientEntry)
	mockL1Status = types.StatusActive
	wantMembershipCheck = false
	wantClientId = 0
	wantHeight = types.Height{}
	wantProof = nil
	wantKey = nil
	wantValue = nil
	if !core.HasClient(mockL1ClientType) {
		core.RegisterClient(cross(cur), mockL1ClientType, mockL1Client{})
	}
	if !core.HasClient(ClientType) {
		Register(cross(cur))
	}
}

func createMockL1Client(cur realm) types.ClientId {
	return core.CreateClient(cross(cur), types.NewMsgCreateClient(mockL1ClientType, nil, nil))
}

func installLensClient(clientId types.ClientId, cs ics23mpt.ClientState, cons ics23mpt.ConsensusState) {
	entries[clientId] = &clientEntry{
		consensusStates: map[ics23mpt.Height]ics23mpt.ConsensusState{
			cs.L2LatestHeight: cons,
		},
		cs: cs,
	}
}

func TestMutatingEntrypointsRequireCoreCaller(cur realm, t *testing.T) {
	resetTestState(cur)
	adapter := Adapter{}

	uassert.AbortsContains(t, cur, "statelensics23mpt: core only", func(cur realm) {
		adapter.CreateClient(cross(cur), types.ClientId(1), nil, nil)
	})
	uassert.AbortsContains(t, cur, "statelensics23mpt: core only", func(cur realm) {
		adapter.UpdateClient(cross(cur), types.ClientId(1), nil)
	})
}

func TestUpdateClientVerifiesL2ConsensusStateOnL1(cur realm, t *testing.T) {
	resetTestState(cur)
	l1ClientId := createMockL1Client(cur)
	l2ClientId := types.ClientId(7)

	cs := ics23mpt.ClientState{
		L2ChainID:         "l2",
		L1ClientID:        uint32(l1ClientId),
		L2ClientID:        uint32(l2ClientId),
		L2LatestHeight:    10,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	initial := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	initialBytes, err := ics23mpt.EncodeConsensusState(initial)
	if err != nil {
		t.Fatalf("EncodeConsensusState initial: %v", err)
	}
	csBytes, err := ics23mpt.EncodeClientState(cs)
	if err != nil {
		t.Fatalf("EncodeClientState: %v", err)
	}
	lensClientId := core.CreateClient(cross(cur), types.NewMsgCreateClient(ClientType, csBytes, initialBytes))

	l2Consensus := makeConsensusBytes(12345, bytes.Repeat([]byte{0xaa}, 32), bytes.Repeat([]byte{0xbb}, 32))
	header := ics23mpt.Header{
		L1Height:              20,
		L2Height:              11,
		L2ConsensusStateProof: []byte("l1-proof"),
		L2ConsensusState:      l2Consensus,
	}
	wantPath := types.ConsensusStatePath(l2ClientId, types.NewHeight(uint64(header.L2Height)))
	wantValueHash := keccak256.Sum256(l2Consensus)
	wantMembershipCheck = true
	wantClientId = l1ClientId
	wantHeight = types.NewHeight(uint64(header.L1Height))
	wantProof = []byte("l1-proof")
	wantKey = wantPath[:]
	wantValue = wantValueHash[:]

	headerBytes, err := ics23mpt.EncodeHeader(header)
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}
	height := core.UpdateClient(cross(cur), types.NewMsgUpdateClient(lensClientId, headerBytes))

	if height != types.NewHeight(uint64(header.L2Height)) {
		t.Fatalf("update height: got %v want %d", height, header.L2Height)
	}
	gotCons := getEntry(lensClientId).consensusStates[ics23mpt.Height(header.L2Height)]
	if gotCons.Timestamp != 12345 ||
		!bytes.Equal(gotCons.StateRoot, bytes.Repeat([]byte{0xaa}, 32)) ||
		!bytes.Equal(gotCons.StorageRoot, bytes.Repeat([]byte{0xbb}, 32)) {
		t.Fatalf("unexpected extracted consensus state: %#v", gotCons)
	}
	adapter := Adapter{}
	if adapter.GetLatestHeight(lensClientId) != types.NewHeight(uint64(header.L2Height)) {
		t.Fatalf("latest height not advanced")
	}
	if adapter.GetTimestamp(lensClientId, types.NewHeight(uint64(header.L2Height))) != types.Timestamp(12345) {
		t.Fatalf("timestamp not stored")
	}
}

func TestGetStatusMirrorsL1Client(cur realm, t *testing.T) {
	resetTestState(cur)
	l1ClientId := createMockL1Client(cur)
	lensClientId := types.ClientId(100)

	cs := ics23mpt.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	adapter := Adapter{}
	installLensClient(lensClientId, cs, cons)

	mockL1Status = types.StatusFrozen
	got := adapter.GetStatus(lensClientId)
	if got != types.StatusFrozen {
		t.Fatalf("GetStatus: got %d want %d", got, types.StatusFrozen)
	}
}

func TestGetStatusReturnsFrozenWhenL1ClientMissing(cur realm, t *testing.T) {
	resetTestState(cur)
	lensClientId := types.ClientId(105)

	cs := ics23mpt.ClientState{L2ChainID: "l2", L1ClientID: 999999, L2LatestHeight: 1}
	cons := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	adapter := Adapter{}
	installLensClient(lensClientId, cs, cons)

	got := adapter.GetStatus(lensClientId)
	if got != types.StatusFrozen {
		t.Fatalf("GetStatus: got %d want %d", got, types.StatusFrozen)
	}
}

func TestVerifyMembershipStorageProof(cur realm, t *testing.T) {
	resetTestState(cur)
	l1ClientId := createMockL1Client(cur)
	lensClientId := types.ClientId(102)
	path := bytes.Repeat([]byte{0x11}, 32)
	value := storage.WordFromUint64(0xdeadbeef)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	root, proofNodes := storageProofFixture(slot[:], value)

	cs := ics23mpt.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: root[:],
	}
	adapter := Adapter{}
	installLensClient(lensClientId, cs, cons)

	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: value,
		Proof: proofNodes,
	})
	adapter.VerifyMembership(lensClientId, types.NewHeight(1), proof, path, value)
}

func TestVerifyMembershipAndNonMembershipRejectInactiveBeforeProofDecode(cur realm, t *testing.T) {
	testCases := []struct {
		name   string
		status types.Status
	}{
		{"frozen", types.StatusFrozen},
		{"expired", types.StatusExpired},
	}
	for _, tc := range testCases {
		t.Run(tc.name+"/membership", func(t *testing.T) {
			adapter, lensClientId := createLensClientForInactiveTest(cur, t)
			mockL1Status = tc.status
			uassert.AbortsContains(t, cur, "statelensics23mpt: client is not active", func(cur realm) {
				adapter.VerifyMembership(lensClientId, types.NewHeight(1), []byte{0xff}, []byte("key"), []byte("value"))
			})
		})
		t.Run(tc.name+"/non-membership", func(t *testing.T) {
			adapter, lensClientId := createLensClientForInactiveTest(cur, t)
			mockL1Status = tc.status
			uassert.AbortsContains(t, cur, "statelensics23mpt: client is not active", func(cur realm) {
				adapter.VerifyNonMembership(lensClientId, types.NewHeight(1), []byte{0xff}, []byte("key"))
			})
		})
	}
}

func TestVerifyNonMembershipStorageProof(cur realm, t *testing.T) {
	resetTestState(cur)
	l1ClientId := createMockL1Client(cur)
	lensClientId := types.ClientId(103)
	path := bytes.Repeat([]byte{0x22}, 32)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	emptyRoot := keccak256.Sum256(rlp.EncodeBytes(nil))

	cs := ics23mpt.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: emptyRoot[:],
	}
	adapter := Adapter{}
	installLensClient(lensClientId, cs, cons)

	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: make([]byte, 32),
	})
	adapter.VerifyNonMembership(lensClientId, types.NewHeight(1), proof, path)
}

func TestVerifyMembershipRejectsWrongCommitmentKey(cur realm, t *testing.T) {
	resetTestState(cur)
	l1ClientId := createMockL1Client(cur)
	lensClientId := types.ClientId(104)

	cs := ics23mpt.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	adapter := Adapter{}
	installLensClient(lensClientId, cs, cons)

	proof := storage.EncodeProof(storage.Proof{
		Key:   storage.WordFromUint64(2),
		Value: storage.WordFromUint64(0xdeadbeef),
	})
	uassert.AbortsContains(t, cur, ics23mpt.ErrInvalidCommitmentKey.Error(), func(cur realm) {
		adapter.VerifyMembership(lensClientId, types.NewHeight(1), proof, bytes.Repeat([]byte{0x11}, 32), storage.WordFromUint64(0xdeadbeef))
	})
}

func TestPacketRecvUsesStateLensStorageProof(cur realm, t *testing.T) {
	flow := setupStateLensOpenChannel(cur, t)
	packet := core.NewPacket(cross(cur), flow.counterpartyChannelId, flow.channelId, []byte("payload"), 1<<62)
	packetKey := types.BatchPacketsPath(mustCommitPackets([]types.Packet{packet}))
	_, proof := updateLensRootForPathValue(cur, t, flow.lensClientId, flow.l1ClientId, flow.l2ClientId, 5, packetKey[:], types.COMMITMENT_MAGIC[:])
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, proof, 5))

	if flow.app.recvCount != 1 {
		t.Fatalf("OnRecvPacket calls: got %d want 1", flow.app.recvCount)
	}
	if !core.HasPacketReceipt(cross(cur), packet) {
		t.Fatal("PacketRecv must set packet receipt after state-lens proof verification")
	}
	if !core.HasAcknowledgement(cross(cur), packet) {
		t.Fatal("PacketRecv must commit acknowledgement after state-lens proof verification")
	}
}

func TestPacketRecvRejectsWrongStateLensStorageProof(cur realm, t *testing.T) {
	flow := setupStateLensOpenChannel(cur, t)
	packet := core.NewPacket(cross(cur), flow.counterpartyChannelId, flow.channelId, []byte("payload"), 101)
	wrongPath := bytes.Repeat([]byte{0x33}, 32)
	_, proof := updateLensRootForPathValue(cur, t, flow.lensClientId, flow.l1ClientId, flow.l2ClientId, 5, wrongPath, types.COMMITMENT_MAGIC[:])

	uassert.AbortsContains(t, cur, ics23mpt.ErrInvalidCommitmentKey.Error(), func(cur realm) {
		core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, proof, 5))
	})
	if flow.app.recvCount != 0 {
		t.Fatalf("OnRecvPacket calls after bad proof: got %d want 0", flow.app.recvCount)
	}
	if core.HasPacketReceipt(cross(cur), packet) {
		t.Fatal("PacketRecv must not set packet receipt after bad state-lens proof")
	}
}

func makeConsensusBytes(timestamp uint64, stateRoot, storageRoot []byte) []byte {
	out := make([]byte, 72)
	copy(out[0:32], stateRoot)
	copy(out[32:64], storageRoot)
	out[64] = byte(timestamp >> 56)
	out[65] = byte(timestamp >> 48)
	out[66] = byte(timestamp >> 40)
	out[67] = byte(timestamp >> 32)
	out[68] = byte(timestamp >> 24)
	out[69] = byte(timestamp >> 16)
	out[70] = byte(timestamp >> 8)
	out[71] = byte(timestamp)
	return out
}

func storageProofFixture(slot []byte, value []byte) ([32]byte, [][]byte) {
	path, err := storage.StoragePath(slot)
	if err != nil {
		panic(err)
	}
	leaf := rlp.EncodeList(rlp.EncodeBytes(compactEncode(true, nibbles(path[:]))), rlp.EncodeBytes(mustStorageValue(value)))
	root := keccak256.Sum256(leaf)
	return root, [][]byte{leaf}
}

func setupStateLensOpenChannel(cur realm, t *testing.T) stateLensFlow {
	t.Helper()
	resetTestState(cur)
	*stateLensTestApp = flowApp{}
	portId := []byte(stateLensTestPortId)
	l1ClientId := createMockL1Client(cur)
	l2ClientId := types.ClientId(77)
	counterpartyClientId := types.ClientId(88)
	counterpartyConnectionId := types.ConnectionId(99)
	counterpartyChannelId := types.ChannelId(100)
	if !core.HasApp(portId) {
		core.RegisterApp(cross(cur), stateLensTestApp)
	}

	cs := ics23mpt.ClientState{
		L2ChainID:         "l2",
		L1ClientID:        uint32(l1ClientId),
		L2ClientID:        uint32(l2ClientId),
		L2LatestHeight:    1,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	cons := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	consBytes, err := ics23mpt.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	csBytes, err := ics23mpt.EncodeClientState(cs)
	if err != nil {
		t.Fatalf("EncodeClientState: %v", err)
	}
	lensClientId := core.CreateClient(cross(cur), types.NewMsgCreateClient(ClientType, csBytes, consBytes))

	connInit := core.NewConnection(cross(cur), types.ConnectionStateInit, counterpartyClientId, lensClientId, 0)
	connInitKey := types.ConnectionPath(counterpartyConnectionId)
	connInitValue := hashBytes(mustEncodeABI(connInit.EncodeABI()))
	_, proof := updateLensRootForPathValue(cur, t, lensClientId, l1ClientId, l2ClientId, 2, connInitKey[:], connInitValue[:])
	connectionId := core.ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(lensClientId, counterpartyClientId, counterpartyConnectionId, proof, 2))

	connOpen := core.NewConnection(cross(cur), types.ConnectionStateOpen, counterpartyClientId, lensClientId, connectionId)
	connOpenValue := hashBytes(mustEncodeABI(connOpen.EncodeABI()))
	_, proof = updateLensRootForPathValue(cur, t, lensClientId, l1ClientId, l2ClientId, 3, connInitKey[:], connOpenValue[:])
	core.ConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(connectionId, proof, 3))

	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, []byte("counterparty-port"), connectionId, "ics-test-1"))

	channelKey := types.ChannelPath(counterpartyChannelId)
	channelTryValue := hashChannel(t, types.ChannelStateTryOpen, counterpartyConnectionId, channelId, portId, "ics-test-1")
	_, proof = updateLensRootForPathValue(cur, t, lensClientId, l1ClientId, l2ClientId, 4, channelKey[:], channelTryValue[:])
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, "ics-test-1", counterpartyChannelId, proof, 4))

	return stateLensFlow{
		app:                   stateLensTestApp,
		l1ClientId:            l1ClientId,
		l2ClientId:            l2ClientId,
		lensClientId:          lensClientId,
		channelId:             channelId,
		counterpartyChannelId: counterpartyChannelId,
	}
}

func createLensClientForInactiveTest(cur realm, t *testing.T) (Adapter, types.ClientId) {
	t.Helper()
	resetTestState(cur)
	l1ClientId := createMockL1Client(cur)
	lensClientId := types.ClientId(101)

	cs := ics23mpt.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	adapter := Adapter{}
	installLensClient(lensClientId, cs, cons)
	return adapter, lensClientId
}

func proofForPathValue(t *testing.T, path []byte, value []byte) ([32]byte, []byte) {
	t.Helper()
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	root, nodes := storageProofFixture(slot[:], value)
	return root, storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: value,
		Proof: nodes,
	})
}

func updateLensRootForPathValue(cur realm, t *testing.T, lensClientId types.ClientId, l1ClientId types.ClientId, l2ClientId types.ClientId, height uint64, path []byte, value []byte) ([32]byte, []byte) {
	t.Helper()
	root, proof := proofForPathValue(t, path, value)
	l2Consensus := makeConsensusBytes(height, bytes.Repeat([]byte{0xaa}, 32), root[:])
	header := ics23mpt.Header{
		L1Height:              height,
		L2Height:              height,
		L2ConsensusStateProof: []byte{byte(height)},
		L2ConsensusState:      l2Consensus,
	}
	wantPath := types.ConsensusStatePath(l2ClientId, types.NewHeight(height))
	wantValueHash := keccak256.Sum256(l2Consensus)
	wantMembershipCheck = true
	wantClientId = l1ClientId
	wantHeight = types.NewHeight(height)
	wantProof = header.L2ConsensusStateProof
	wantKey = wantPath[:]
	wantValue = wantValueHash[:]
	headerBytes, err := ics23mpt.EncodeHeader(header)
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(lensClientId, headerBytes))
	return root, proof
}

func hashBytes(b []byte) [32]byte {
	return keccak256.Sum256(b)
}

func mustEncodeABI(b []byte, err error) []byte {
	if err != nil {
		panic(err)
	}
	return b
}

func mustCommitPackets(packets []types.Packet) types.H256 {
	h, err := types.CommitPackets(packets)
	if err != nil {
		panic(err)
	}
	return h
}

func hashChannel(t *testing.T, state types.ChannelState, connectionId types.ConnectionId, counterpartyChannelId types.ChannelId, counterpartyPortId []byte, version string) [32]byte {
	t.Helper()
	schema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint8},
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
		{Type: abi.TypeBytes},
		{Type: abi.TypeString},
	}}
	bz, err := abi.Encode(schema, []any{
		uint8(state),
		uint32(connectionId),
		uint32(counterpartyChannelId),
		counterpartyPortId,
		version,
	})
	if err != nil {
		t.Fatalf("Encode channel: %v", err)
	}
	return keccak256.Sum256(encodeTopLevelDynamic(bz))
}

func encodeTopLevelDynamic(encoded []byte) []byte {
	out := make([]byte, 0, 32+len(encoded))
	out = append(out, u64ToH256(32)...)
	return append(out, encoded...)
}

func u64ToH256(v uint64) []byte {
	out := make([]byte, 32)
	out[24] = byte(v >> 56)
	out[25] = byte(v >> 48)
	out[26] = byte(v >> 40)
	out[27] = byte(v >> 32)
	out[28] = byte(v >> 24)
	out[29] = byte(v >> 16)
	out[30] = byte(v >> 8)
	out[31] = byte(v)
	return out
}

func mustStorageValue(value []byte) []byte {
	out, err := storage.EncodeStorageValue(value)
	if err != nil {
		panic(err)
	}
	return out
}

func nibbles(key []byte) []byte {
	out := make([]byte, 0, len(key)*2)
	for _, b := range key {
		out = append(out, b>>4, b&0x0f)
	}
	return out
}

func compactEncode(leaf bool, ns []byte) []byte {
	flag := byte(0)
	if leaf {
		flag = 2
	}
	odd := len(ns)%2 == 1
	out := make([]byte, 0, (len(ns)+2)/2)
	if odd {
		out = append(out, (flag+1)<<4|ns[0])
		ns = ns[1:]
	} else {
		out = append(out, flag<<4)
	}
	for i := 0; i < len(ns); i += 2 {
		out = append(out, ns[i]<<4|ns[i+1])
	}
	return out
}
