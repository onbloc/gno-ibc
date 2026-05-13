package statelensics23mpt

import (
	"bytes"
	"crypto/keccak256"
	"testing"

	"gno.land/p/core/encoding/abi"
	"gno.land/p/core/encoding/rlp"
	"gno.land/p/core/ethereum/storage"
	statelensp "gno.land/p/core/ibc/lightclients/statelensics23mpt"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/core/ibc/v1/core"
)

const mockL1ClientType core.ClientType = "mock-state-lens-l1"

var (
	mockL1Status        core.Status
	wantMembershipCheck bool
	wantClientId        core.ClientId
	wantHeight          core.Height
	wantProof           []byte
	wantKey             []byte
	wantValue           []byte
)

type mockL1Client struct{}

func (mockL1Client) CreateClient(_ realm, _ core.ClientId, _, _ []byte) string { return "l1" }
func (mockL1Client) UpdateClient(_ realm, _ core.ClientId, _ []byte) core.ConsensusStateUpdate {
	return core.ConsensusStateUpdate{}
}
func (mockL1Client) VerifyMembership(clientId core.ClientId, height core.Height, proof, key, value []byte) {
	if !wantMembershipCheck {
		panic("unexpected membership verification")
	}
	if clientId != wantClientId || height != wantHeight {
		panic("membership target mismatch")
	}
	if !equalBytes(proof, wantProof) || !equalBytes(key, wantKey) || !equalBytes(value, wantValue) {
		panic("membership proof payload mismatch")
	}
}
func (mockL1Client) VerifyNonMembership(_ core.ClientId, _ core.Height, _, _ []byte) {}
func (mockL1Client) GetTimestamp(_ core.ClientId, _ core.Height) core.Timestamp      { return 0 }
func (mockL1Client) GetLatestHeight(_ core.ClientId) core.Height                     { return 0 }
func (mockL1Client) GetStatus(_ core.ClientId) core.Status                           { return mockL1Status }

type flowApp struct {
	recvCount int
}

func (a *flowApp) OnChannelOpenInit(_ core.ConnectionId, _ core.ChannelId, _ string, _ address) {
}
func (a *flowApp) OnChannelOpenTry(_ core.ConnectionId, _ core.ChannelId, _, _ string, _ address) {
}
func (a *flowApp) OnChannelOpenAck(_ core.ChannelId, _ core.ChannelId, _ string, _ address) {}
func (a *flowApp) OnChannelOpenConfirm(_ core.ChannelId, _ address)                         {}
func (a *flowApp) OnChannelCloseInit(_ core.ChannelId, _ address)                           {}
func (a *flowApp) OnChannelCloseConfirm(_ core.ChannelId, _ address)                        {}
func (a *flowApp) OnRecvPacket(_ core.Packet, _ address, _ []byte) core.RecvPacketResult {
	a.recvCount++
	return core.RecvPacketResult{Status: core.PacketStatusSuccess, Ack: []byte{0x01}}
}
func (a *flowApp) OnIntentRecvPacket(_ core.Packet, _ address, _ []byte) {}
func (a *flowApp) OnAcknowledgementPacket(_ core.Packet, _ []byte, _ address) {
}
func (a *flowApp) OnTimeoutPacket(_ core.Packet, _ address) {}

type stateLensFlow struct {
	app                   *flowApp
	l1ClientId            core.ClientId
	l2ClientId            core.ClientId
	lensClientId          core.ClientId
	channelId             core.ChannelId
	counterpartyChannelId core.ChannelId
}

func resetTestState() {
	entries = make(map[core.ClientId]*clientEntry)
	mockL1Status = core.StatusActive
	wantMembershipCheck = false
	wantClientId = 0
	wantHeight = 0
	wantProof = nil
	wantKey = nil
	wantValue = nil
	if !core.HasClient(mockL1ClientType) {
		core.RegisterClient(cross, mockL1ClientType, mockL1Client{})
	}
	if !core.HasClient(ClientType) {
		core.RegisterClient(cross, ClientType, Adapter{})
	}
}

func createMockL1Client() core.ClientId {
	return core.CreateClient(cross, core.MsgCreateClient{ClientType: mockL1ClientType})
}

func TestUpdateClientVerifiesL2ConsensusStateOnL1(t *testing.T) {
	resetTestState()
	l1ClientId := createMockL1Client()
	lensClientId := core.ClientId(99)
	l2ClientId := core.ClientId(7)

	cs := statelensp.ClientState{
		L2ChainID:         "l2",
		L1ClientID:        uint32(l1ClientId),
		L2ClientID:        uint32(l2ClientId),
		L2LatestHeight:    10,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	initial := statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	initialBytes, err := statelensp.EncodeConsensusState(initial)
	if err != nil {
		t.Fatalf("EncodeConsensusState initial: %v", err)
	}
	adapter := Adapter{}
	adapter.CreateClient(cross, lensClientId, statelensp.EncodeClientState(cs), initialBytes)

	l2Consensus := makeConsensusBytes(12345, bytes.Repeat([]byte{0xaa}, 32), bytes.Repeat([]byte{0xbb}, 32))
	header := statelensp.Header{
		L1Height:              20,
		L2Height:              11,
		L2ConsensusStateProof: []byte("l1-proof"),
		L2ConsensusState:      l2Consensus,
	}
	wantPath := core.ConsensusStatePath(l2ClientId, core.Height(header.L2Height))
	wantValueHash := keccak256.Sum256(l2Consensus)
	wantMembershipCheck = true
	wantClientId = l1ClientId
	wantHeight = core.Height(header.L1Height)
	wantProof = []byte("l1-proof")
	wantKey = cloneBytes(wantPath[:])
	wantValue = cloneBytes(wantValueHash[:])

	update := adapter.UpdateClient(cross, lensClientId, statelensp.EncodeHeader(header))

	if update.Height != core.Height(header.L2Height) {
		t.Fatalf("update height: got %d want %d", update.Height, header.L2Height)
	}
	gotCons, err := statelensp.DecodeConsensusState(update.ConsensusStateBytes)
	if err != nil {
		t.Fatalf("DecodeConsensusState update: %v", err)
	}
	if gotCons.Timestamp != 12345 ||
		!bytes.Equal(gotCons.StateRoot, bytes.Repeat([]byte{0xaa}, 32)) ||
		!bytes.Equal(gotCons.StorageRoot, bytes.Repeat([]byte{0xbb}, 32)) {
		t.Fatalf("unexpected extracted consensus state: %#v", gotCons)
	}
	if adapter.GetLatestHeight(lensClientId) != core.Height(header.L2Height) {
		t.Fatalf("latest height not advanced")
	}
	if adapter.GetTimestamp(lensClientId, core.Height(header.L2Height)) != core.Timestamp(12345) {
		t.Fatalf("timestamp not stored")
	}
}

func TestGetStatusMirrorsL1Client(t *testing.T) {
	resetTestState()
	l1ClientId := createMockL1Client()
	lensClientId := core.ClientId(100)

	cs := statelensp.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	consBytes, err := statelensp.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	adapter := Adapter{}
	adapter.CreateClient(cross, lensClientId, statelensp.EncodeClientState(cs), consBytes)

	mockL1Status = core.StatusFrozen
	got := adapter.GetStatus(lensClientId)
	if got != core.StatusFrozen {
		t.Fatalf("GetStatus: got %d want %d", got, core.StatusFrozen)
	}
}

func TestVerifyMembershipStorageProof(t *testing.T) {
	resetTestState()
	l1ClientId := createMockL1Client()
	lensClientId := core.ClientId(102)
	path := bytes.Repeat([]byte{0x11}, 32)
	value := storage.WordFromUint64(0xdeadbeef)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	root, proofNodes := storageProofFixture(slot[:], value)

	cs := statelensp.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: root[:],
	}
	consBytes, err := statelensp.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	adapter := Adapter{}
	adapter.CreateClient(cross, lensClientId, statelensp.EncodeClientState(cs), consBytes)

	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: value,
		Proof: proofNodes,
	})
	adapter.VerifyMembership(lensClientId, core.Height(1), proof, path, value)
}

func TestVerifyMembershipAndNonMembershipRejectInactiveBeforeProofDecode(t *testing.T) {
	testCases := []struct {
		name   string
		status core.Status
	}{
		{"frozen", core.StatusFrozen},
		{"expired", core.StatusExpired},
	}
	for _, tc := range testCases {
		t.Run(tc.name+"/membership", func(t *testing.T) {
			adapter, lensClientId := createLensClientForInactiveTest(t)
			mockL1Status = tc.status
			uassert.AbortsContains(t, "statelensics23mpt: client is not active", func(cur realm) {
				adapter.VerifyMembership(lensClientId, core.Height(1), []byte{0xff}, []byte("key"), []byte("value"))
			})
		})
		t.Run(tc.name+"/non-membership", func(t *testing.T) {
			adapter, lensClientId := createLensClientForInactiveTest(t)
			mockL1Status = tc.status
			uassert.AbortsContains(t, "statelensics23mpt: client is not active", func(cur realm) {
				adapter.VerifyNonMembership(lensClientId, core.Height(1), []byte{0xff}, []byte("key"))
			})
		})
	}
}

func TestVerifyNonMembershipStorageProof(t *testing.T) {
	resetTestState()
	l1ClientId := createMockL1Client()
	lensClientId := core.ClientId(103)
	path := bytes.Repeat([]byte{0x22}, 32)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	emptyRoot := keccak256.Sum256(rlp.EncodeBytes(nil))

	cs := statelensp.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: emptyRoot[:],
	}
	consBytes, err := statelensp.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	adapter := Adapter{}
	adapter.CreateClient(cross, lensClientId, statelensp.EncodeClientState(cs), consBytes)

	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: make([]byte, 32),
	})
	adapter.VerifyNonMembership(lensClientId, core.Height(1), proof, path)
}

func TestVerifyMembershipRejectsWrongCommitmentKey(t *testing.T) {
	resetTestState()
	l1ClientId := createMockL1Client()
	lensClientId := core.ClientId(104)

	cs := statelensp.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	consBytes, err := statelensp.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	adapter := Adapter{}
	adapter.CreateClient(cross, lensClientId, statelensp.EncodeClientState(cs), consBytes)

	proof := storage.EncodeProof(storage.Proof{
		Key:   storage.WordFromUint64(2),
		Value: storage.WordFromUint64(0xdeadbeef),
	})
	uassert.AbortsContains(t, ErrInvalidCommitmentKey.Error(), func(cur realm) {
		adapter.VerifyMembership(lensClientId, core.Height(1), proof, bytes.Repeat([]byte{0x11}, 32), storage.WordFromUint64(0xdeadbeef))
	})
}

func TestPacketRecvUsesStateLensStorageProof(t *testing.T) {
	flow := setupStateLensOpenChannel(t, []byte("statelens-flow-port-ok"))
	packet := core.Packet{
		SourceChannelId:      flow.counterpartyChannelId,
		DestinationChannelId: flow.channelId,
		Data:                 []byte("payload"),
		TimeoutTimestamp:     100,
	}
	packetKey := core.BatchPacketsPath(core.CommitPackets([]core.Packet{packet}))
	_, proof := updateLensRootForPathValue(t, flow.lensClientId, flow.l1ClientId, flow.l2ClientId, 5, packetKey[:], core.COMMITMENT_MAGIC[:])
	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		Proof:       proof,
		ProofHeight: 5,
	})

	if flow.app.recvCount != 1 {
		t.Fatalf("OnRecvPacket calls: got %d want 1", flow.app.recvCount)
	}
	if !core.HasPacketReceipt(cross, packet) {
		t.Fatal("PacketRecv must set packet receipt after state-lens proof verification")
	}
	if !core.HasAcknowledgement(cross, packet) {
		t.Fatal("PacketRecv must commit acknowledgement after state-lens proof verification")
	}
}

func TestPacketRecvRejectsWrongStateLensStorageProof(t *testing.T) {
	flow := setupStateLensOpenChannel(t, []byte("statelens-flow-port-bad-proof"))
	packet := core.Packet{
		SourceChannelId:      flow.counterpartyChannelId,
		DestinationChannelId: flow.channelId,
		Data:                 []byte("payload"),
		TimeoutTimestamp:     101,
	}
	wrongPath := bytes.Repeat([]byte{0x33}, 32)
	_, proof := updateLensRootForPathValue(t, flow.lensClientId, flow.l1ClientId, flow.l2ClientId, 5, wrongPath, core.COMMITMENT_MAGIC[:])

	uassert.AbortsContains(t, ErrInvalidCommitmentKey.Error(), func(cur realm) {
		core.PacketRecv(cross, core.MsgPacketRecv{
			Packets:     []core.Packet{packet},
			Proof:       proof,
			ProofHeight: 5,
		})
	})
	if flow.app.recvCount != 0 {
		t.Fatalf("OnRecvPacket calls after bad proof: got %d want 0", flow.app.recvCount)
	}
	if core.HasPacketReceipt(cross, packet) {
		t.Fatal("PacketRecv must not set packet receipt after bad state-lens proof")
	}
}

func TestExtractConsensusStateRejectsShortData(t *testing.T) {
	_, err := extractConsensusState([]byte{0x01}, statelensp.ClientState{
		TimestampOffset:   0,
		StateRootOffset:   0,
		StorageRootOffset: 0,
	})
	if err != ErrConsensusStateTooShort {
		t.Fatalf("extractConsensusState: got %v want %v", err, ErrConsensusStateTooShort)
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

func cloneBytes(b []byte) []byte {
	out := make([]byte, len(b))
	copy(out, b)
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

func setupStateLensOpenChannel(t *testing.T, portId []byte) stateLensFlow {
	t.Helper()
	resetTestState()
	l1ClientId := createMockL1Client()
	l2ClientId := core.ClientId(77)
	counterpartyClientId := core.ClientId(88)
	counterpartyConnectionId := core.ConnectionId(99)
	counterpartyChannelId := core.ChannelId(100)
	app := &flowApp{}
	if core.HasApp(portId) {
		t.Fatalf("test port already registered: %s", string(portId))
	}
	core.RegisterApp(cross, portId, app)

	cs := statelensp.ClientState{
		L2ChainID:         "l2",
		L1ClientID:        uint32(l1ClientId),
		L2ClientID:        uint32(l2ClientId),
		L2LatestHeight:    1,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	cons := statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	consBytes, err := statelensp.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	lensClientId := core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          ClientType,
		ClientStateBytes:    statelensp.EncodeClientState(cs),
		ConsensusStateBytes: consBytes,
	})

	connInit := core.Connection{
		State:                    core.ConnectionStateInit,
		ClientId:                 counterpartyClientId,
		CounterpartyClientId:     lensClientId,
		CounterpartyConnectionId: 0,
	}
	connInitKey := core.ConnectionPath(counterpartyConnectionId)
	connInitValue := hashBytes(connInit.EthAbiEncode())
	_, proof := updateLensRootForPathValue(t, lensClientId, l1ClientId, l2ClientId, 2, connInitKey[:], connInitValue[:])
	connectionId := core.ConnectionOpenTry(cross, core.MsgConnectionOpenTry{
		ClientId:                 lensClientId,
		CounterpartyClientId:     counterpartyClientId,
		CounterpartyConnectionId: counterpartyConnectionId,
		ProofInit:                proof,
		ProofHeight:              2,
	})

	connOpen := core.Connection{
		State:                    core.ConnectionStateOpen,
		ClientId:                 counterpartyClientId,
		CounterpartyClientId:     lensClientId,
		CounterpartyConnectionId: connectionId,
	}
	connOpenValue := hashBytes(connOpen.EthAbiEncode())
	_, proof = updateLensRootForPathValue(t, lensClientId, l1ClientId, l2ClientId, 3, connInitKey[:], connOpenValue[:])
	core.ConnectionOpenConfirm(cross, core.MsgConnectionOpenConfirm{
		ConnectionId: connectionId,
		ProofAck:     proof,
		ProofHeight:  3,
	})

	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             portId,
		CounterpartyPortId: []byte("counterparty-port"),
		ConnectionId:       connectionId,
		Version:            "ics-test-1",
	})

	channelKey := core.ChannelPath(counterpartyChannelId)
	channelTryValue := hashChannel(t, core.ChannelStateTryOpen, counterpartyConnectionId, channelId, portId, "ics-test-1")
	_, proof = updateLensRootForPathValue(t, lensClientId, l1ClientId, l2ClientId, 4, channelKey[:], channelTryValue[:])
	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   "ics-test-1",
		CounterpartyChannelId: counterpartyChannelId,
		ProofTry:              proof,
		ProofHeight:           4,
	})

	return stateLensFlow{
		app:                   app,
		l1ClientId:            l1ClientId,
		l2ClientId:            l2ClientId,
		lensClientId:          lensClientId,
		channelId:             channelId,
		counterpartyChannelId: counterpartyChannelId,
	}
}

func createLensClientForInactiveTest(t *testing.T) (Adapter, core.ClientId) {
	t.Helper()
	resetTestState()
	l1ClientId := createMockL1Client()
	lensClientId := core.ClientId(101)

	cs := statelensp.ClientState{L2ChainID: "l2", L1ClientID: uint32(l1ClientId), L2LatestHeight: 1}
	cons := statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	}
	consBytes, err := statelensp.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	adapter := Adapter{}
	adapter.CreateClient(cross, lensClientId, statelensp.EncodeClientState(cs), consBytes)
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

func updateLensRootForPathValue(t *testing.T, lensClientId core.ClientId, l1ClientId core.ClientId, l2ClientId core.ClientId, height uint64, path []byte, value []byte) ([32]byte, []byte) {
	t.Helper()
	root, proof := proofForPathValue(t, path, value)
	l2Consensus := makeConsensusBytes(height, bytes.Repeat([]byte{0xaa}, 32), root[:])
	header := statelensp.Header{
		L1Height:              height,
		L2Height:              height,
		L2ConsensusStateProof: []byte{byte(height)},
		L2ConsensusState:      l2Consensus,
	}
	wantPath := core.ConsensusStatePath(l2ClientId, core.Height(height))
	wantValueHash := keccak256.Sum256(l2Consensus)
	wantMembershipCheck = true
	wantClientId = l1ClientId
	wantHeight = core.Height(height)
	wantProof = cloneBytes(header.L2ConsensusStateProof)
	wantKey = cloneBytes(wantPath[:])
	wantValue = cloneBytes(wantValueHash[:])
	core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      lensClientId,
		ClientMessage: statelensp.EncodeHeader(header),
	})
	return root, proof
}

func hashBytes(b []byte) [32]byte {
	return keccak256.Sum256(b)
}

func hashChannel(t *testing.T, state core.ChannelState, connectionId core.ConnectionId, counterpartyChannelId core.ChannelId, counterpartyPortId []byte, version string) [32]byte {
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
	return keccak256.Sum256(bz)
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
