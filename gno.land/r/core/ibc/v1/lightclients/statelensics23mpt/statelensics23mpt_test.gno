package statelensics23mpt

import (
	"bytes"
	"crypto/keccak256"
	"testing"

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

func TestVerifyMembershipRejectsInactiveBeforeProofDecode(t *testing.T) {
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

	mockL1Status = core.StatusFrozen
	uassert.AbortsContains(t, "statelensics23mpt: client is not active", func(cur realm) {
		adapter.VerifyMembership(lensClientId, core.Height(1), []byte{0xff}, []byte("key"), []byte("value"))
	})
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
