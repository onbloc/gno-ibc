package ics23mpt

import (
	"bytes"
	"crypto/keccak256"
	"errors"
	"testing"

	"gno.land/p/onbloc/encoding/rlp"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/p/onbloc/verifier/evm/storage"
)

// mockL1Client is a stub lightclient.Interface standing in for the settlement
// (L1) chain's light client. VerifyMembership records its arguments and returns
// membershipErr; Status returns the configured status.
type mockL1Client struct {
	status lightclient.Status

	membershipErr error
	called        bool
	gotHeight     uint64
	gotKey        []byte
	gotProof      []byte
	gotValue      []byte
}

func (m *mockL1Client) VerifyMembership(height uint64, key, proof, value []byte) error {
	m.called = true
	m.gotHeight = height
	m.gotKey = key
	m.gotProof = proof
	m.gotValue = value
	return m.membershipErr
}

func (m *mockL1Client) VerifyNonMembership(height uint64, key, proof []byte) error { return nil }
func (m *mockL1Client) GetTimestamp() types.Timestamp                              { return 0 }
func (m *mockL1Client) GetTimestampAtHeight(uint64) (types.Timestamp, error)       { return 0, nil }
func (m *mockL1Client) GetLatestHeight() uint64                                    { return 0 }
func (m *mockL1Client) GetCounterpartyChainID() string                             { return "l1" }
func (m *mockL1Client) Status() lightclient.Status                                 { return m.status }

func (m *mockL1Client) VerifyHeader(_ address, _ []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{}, nil
}

func (m *mockL1Client) VerifyCreation(_ address, _ address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockL1Client) Misbehaviour(_ address, _ []byte, _ address) ([]byte, error) {
	return nil, nil
}

// newTestClient builds a client with a single consensus state at L2LatestHeight
// 10 and an active mock L1 client. The L2 consensus blob layout uses
// state_root at offset 0, storage_root at offset 32, timestamp at offset 64
// (see makeConsensusBytes).
func newTestClient(t *testing.T, l1 *mockL1Client, storageRoot []byte) *StateLensIcs23MptLightClient {
	t.Helper()
	cs := &ClientState{
		L2ChainID:         "l2-chain",
		L1ClientID:        1,
		L2ClientID:        7,
		L2LatestHeight:    10,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	cons := &ConsensusState{
		Timestamp:   12345,
		StateRoot:   bytes.Repeat([]byte{0xaa}, 32),
		StorageRoot: storageRoot,
	}
	c, err := newTestStateLensClient(cs, cons, l1)
	if err != nil {
		t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
	}
	return c
}

func TestClientAccessors(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))

	if c.GetLatestHeight() != 10 {
		t.Errorf("GetLatestHeight: got %d want 10", c.GetLatestHeight())
	}
	if c.GetCounterpartyChainID() != "l2-chain" {
		t.Errorf("GetCounterpartyChainID: got %q want l2-chain", c.GetCounterpartyChainID())
	}
	if c.GetTimestamp() != types.Timestamp(12345) {
		t.Errorf("GetTimestamp: got %d want 12345", c.GetTimestamp())
	}
}

func TestClientGetTimestampNoConsensus(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	c.clientState.L2LatestHeight = 999
	if c.GetTimestamp() != 0 {
		t.Errorf("GetTimestamp: got %d want 0", c.GetTimestamp())
	}
}

func TestStatusMirrorsL1(t *testing.T) {
	cases := []struct {
		l1   lightclient.Status
		want lightclient.Status
	}{
		{lightclient.Active, lightclient.Active},
		{lightclient.Expired, lightclient.Expired},
		{lightclient.Frozen, lightclient.Frozen},
		{lightclient.Unknown, lightclient.Frozen},
		{lightclient.Unauthorized, lightclient.Frozen},
	}
	for _, tc := range cases {
		c := newTestClient(t, &mockL1Client{status: tc.l1}, bytes.Repeat([]byte{0x02}, 32))
		if got := c.Status(); got != tc.want {
			t.Errorf("Status with L1=%q: got %q want %q", tc.l1, got, tc.want)
		}
	}
}

func TestStatusNilL1IsFrozen(t *testing.T) {
	cs := &ClientState{L2ChainID: "l2", L2LatestHeight: 1}
	cons := &ConsensusState{Timestamp: 1, StateRoot: bytes.Repeat([]byte{0x01}, 32), StorageRoot: bytes.Repeat([]byte{0x02}, 32)}
	c, err := newTestStateLensClient(cs, cons, nil)
	if err != nil {
		t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
	}
	if got := c.Status(); got != lightclient.Frozen {
		t.Errorf("Status with nil L1: got %q want %q", got, lightclient.Frozen)
	}
}

func TestVerifyHeaderUpdatesState(t *testing.T) {
	l1 := &mockL1Client{status: lightclient.Active}
	c := newTestClient(t, l1, bytes.Repeat([]byte{0x02}, 32))

	l2Consensus := makeConsensusBytes(67890, bytes.Repeat([]byte{0xcc}, 32), bytes.Repeat([]byte{0xdd}, 32))
	header := Header{
		L1Height:              20,
		L2Height:              11,
		L2ConsensusStateProof: []byte("l1-proof"),
		L2ConsensusState:      l2Consensus,
	}
	headerBytes, err := EncodeHeader(header)
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}

	var caller, relayer address
	update, err := c.VerifyHeader(caller, headerBytes, relayer)
	if err != nil {
		t.Fatalf("VerifyHeader: %v", err)
	}
	if update.Height != 11 {
		t.Errorf("update height: got %d want 11", update.Height)
	}

	// The L1 membership check must target the L2 consensus-state path at L1Height
	// with the keccak256 of the L2 consensus blob.
	if !l1.called {
		t.Fatal("expected L1 VerifyMembership to be called")
	}
	if l1.gotHeight != 20 {
		t.Errorf("L1 height: got %d want 20", l1.gotHeight)
	}
	wantPath := types.ConsensusStatePath(types.ClientId(7), types.NewHeight(11))
	if !bytes.Equal(l1.gotKey, wantPath[:]) {
		t.Errorf("L1 key mismatch")
	}
	if !bytes.Equal(l1.gotProof, []byte("l1-proof")) {
		t.Errorf("L1 proof mismatch")
	}
	wantHash := keccak256.Sum256(l2Consensus)
	if !bytes.Equal(l1.gotValue, wantHash[:]) {
		t.Errorf("L1 value mismatch")
	}

	// The extracted consensus state must be stored and the latest height advanced.
	if c.GetLatestHeight() != 11 {
		t.Errorf("latest height: got %d want 11", c.GetLatestHeight())
	}
	got, found := c.getConsensusState(11)
	if !found {
		t.Fatal("consensus state at height 11 not stored")
	}
	if got.Timestamp != 67890 ||
		!bytes.Equal(got.StateRoot, bytes.Repeat([]byte{0xcc}, 32)) ||
		!bytes.Equal(got.StorageRoot, bytes.Repeat([]byte{0xdd}, 32)) {
		t.Fatalf("unexpected extracted consensus state: %#v", got)
	}
}

func TestVerifyHeaderRejectsWhenL1Fails(t *testing.T) {
	l1 := &mockL1Client{status: lightclient.Active, membershipErr: errors.New("boom")}
	c := newTestClient(t, l1, bytes.Repeat([]byte{0x02}, 32))

	header := Header{
		L1Height:              20,
		L2Height:              11,
		L2ConsensusStateProof: []byte("l1-proof"),
		L2ConsensusState:      makeConsensusBytes(1, bytes.Repeat([]byte{0xcc}, 32), bytes.Repeat([]byte{0xdd}, 32)),
	}
	headerBytes, err := EncodeHeader(header)
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}

	var caller, relayer address
	if _, err := c.VerifyHeader(caller, headerBytes, relayer); err == nil {
		t.Fatal("expected VerifyHeader to fail when L1 membership fails")
	}
	// Latest height must not advance on failure.
	if c.GetLatestHeight() != 10 {
		t.Errorf("latest height advanced despite failure: got %d want 10", c.GetLatestHeight())
	}
}

func TestVerifyHeaderNilL1(t *testing.T) {
	cs := &ClientState{L2ChainID: "l2", L2ClientID: 7, L2LatestHeight: 10, StorageRootOffset: 32}
	cons := &ConsensusState{Timestamp: 1, StateRoot: bytes.Repeat([]byte{0x01}, 32), StorageRoot: bytes.Repeat([]byte{0x02}, 32)}
	c, err := newTestStateLensClient(cs, cons, nil)
	if err != nil {
		t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
	}
	var caller, relayer address
	if _, err := c.VerifyHeader(caller, []byte{0x00}, relayer); err != ErrNoL1Client {
		t.Fatalf("VerifyHeader nil L1: got %v want %v", err, ErrNoL1Client)
	}
}

func TestMisbehaviourUnsupported(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	var caller, relayer address
	if _, err := c.Misbehaviour(caller, nil, relayer); err != ErrMisbehaviourUnsupported {
		t.Fatalf("Misbehaviour: got %v want %v", err, ErrMisbehaviourUnsupported)
	}
}

func TestVerifyCreationEmpty(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	var caller, relayer address
	res, err := c.VerifyCreation(caller, relayer)
	if err != nil {
		t.Fatalf("VerifyCreation: %v", err)
	}
	if len(res.ClientStateBytes) != 0 {
		t.Errorf("VerifyCreation must not write a client state")
	}
}

func TestNewStateLensIcs23MptLightClientUsesLazyGetter(t *testing.T) {
	clientState := ClientState{
		L2ChainID:         "reinit-l2",
		L1ClientID:        2,
		L2ClientID:        9,
		L2LatestHeight:    42,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	consensusState := ConsensusState{
		Timestamp:   4242,
		StateRoot:   bytes.Repeat([]byte{0x42}, 32),
		StorageRoot: bytes.Repeat([]byte{0x43}, 32),
	}

	// The getter closes over `current`. Swapping it simulates ForceUpdateClient
	// replacing the L1 light client in the host store without any explicit refresh.
	current := lightclient.Interface(&mockL1Client{status: lightclient.Active})
	getL1ClientFn := func(_ types.ClientId) (lightclient.Interface, bool) {
		return current, current != nil
	}

	c, err := NewStateLensIcs23MptLightClient(&clientState, &consensusState, getL1ClientFn)
	if err != nil {
		t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
	}

	if c.clientState.L1ClientID != 2 {
		t.Fatalf("l1 client id: got %d want 2", c.clientState.L1ClientID)
	}
	if c.GetLatestHeight() != 42 {
		t.Fatalf("latest height: got %d want 42", c.GetLatestHeight())
	}
	if c.GetCounterpartyChainID() != "reinit-l2" {
		t.Fatalf("chain id: got %q want reinit-l2", c.GetCounterpartyChainID())
	}
	got, found := c.getConsensusState(42)
	if !found {
		t.Fatal("consensus state not stored")
	}
	if got.Timestamp != 4242 || !bytes.Equal(got.StorageRoot, bytes.Repeat([]byte{0x43}, 32)) {
		t.Fatalf("unexpected consensus state: %#v", got)
	}

	if s := c.Status(); s != lightclient.Active {
		t.Fatalf("status: got %q want Active", s)
	}

	// Swap to simulate ForceUpdateClient on L1 — the change is visible immediately.
	current = &mockL1Client{status: lightclient.Expired}
	if s := c.Status(); s != lightclient.Expired {
		t.Fatalf("status after L1 swap: got %q want Expired", s)
	}
}

func newTestStateLensClient(cs *ClientState, cons *ConsensusState, l1 lightclient.Interface) (*StateLensIcs23MptLightClient, error) {
	return NewStateLensIcs23MptLightClient(cs, cons, func(_ types.ClientId) (lightclient.Interface, bool) {
		return l1, l1 != nil
	})
}

func TestVerifyMembershipStorageProof(t *testing.T) {
	path := bytes.Repeat([]byte{0x11}, 32)
	value := storage.WordFromUint64(0xdeadbeef)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	root, nodes := storageProofFixture(t, slot[:], value)

	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, root[:])

	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: value,
		Proof: nodes,
	})
	if err := c.VerifyMembership(10, path, proof, value); err != nil {
		t.Fatalf("VerifyMembership: %v", err)
	}
}

func TestVerifyMembershipRejectsWrongCommitmentKey(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	proof := storage.EncodeProof(storage.Proof{
		Key:   storage.WordFromUint64(2),
		Value: storage.WordFromUint64(0xdeadbeef),
	})
	if err := c.VerifyMembership(10, bytes.Repeat([]byte{0x11}, 32), proof, storage.WordFromUint64(0xdeadbeef)); err != ErrInvalidCommitmentKey {
		t.Fatalf("VerifyMembership: got %v want %v", err, ErrInvalidCommitmentKey)
	}
}

func TestVerifyMembershipRejectsValueMismatch(t *testing.T) {
	path := bytes.Repeat([]byte{0x11}, 32)
	value := storage.WordFromUint64(0xdeadbeef)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: value,
	})
	if err := c.VerifyMembership(10, path, proof, storage.WordFromUint64(0xcafe)); err != ErrStoredValueMismatch {
		t.Fatalf("VerifyMembership: got %v want %v", err, ErrStoredValueMismatch)
	}
}

func TestVerifyMembershipRejectsNon32Value(t *testing.T) {
	path := bytes.Repeat([]byte{0x11}, 32)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: make([]byte, 32),
	})
	if err := c.VerifyMembership(10, path, proof, []byte{0x01}); err != ErrInvalidCommitmentValue {
		t.Fatalf("VerifyMembership: got %v want %v", err, ErrInvalidCommitmentValue)
	}
}

func TestVerifyMembershipHeightTooHigh(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	if err := c.VerifyMembership(11, bytes.Repeat([]byte{0x11}, 32), nil, make([]byte, 32)); err != ErrInvalidHeight {
		t.Fatalf("VerifyMembership: got %v want %v", err, ErrInvalidHeight)
	}
}

func TestVerifyMembershipConsensusNotFound(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
	// Height 5 <= latest 10 but no consensus state stored there.
	if err := c.VerifyMembership(5, bytes.Repeat([]byte{0x11}, 32), nil, make([]byte, 32)); err != ErrConsensusStateNotFound {
		t.Fatalf("VerifyMembership: got %v want %v", err, ErrConsensusStateNotFound)
	}
}

func TestVerifyNonMembershipStorageProof(t *testing.T) {
	path := bytes.Repeat([]byte{0x22}, 32)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	emptyRoot := keccak256.Sum256(rlp.EncodeBytes(nil))

	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, emptyRoot[:])
	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: make([]byte, 32),
	})
	if err := c.VerifyNonMembership(10, path, proof); err != nil {
		t.Fatalf("VerifyNonMembership: %v", err)
	}
}

// --- fixtures ---

// makeConsensusBytes lays out an L2 consensus blob matching the offsets used by
// newTestClient: state_root at 0, storage_root at 32, big-endian timestamp at
// 64.
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

// storageProofFixture builds a single-leaf MPT proving slot stores value, and
// returns its root and the proof node list. Mirrors the realm test fixture.
func storageProofFixture(t *testing.T, slot []byte, value []byte) ([32]byte, [][]byte) {
	t.Helper()
	path, err := storage.StoragePath(slot)
	if err != nil {
		t.Fatalf("StoragePath: %v", err)
	}
	storedValue, err := storage.EncodeStorageValue(value)
	if err != nil {
		t.Fatalf("EncodeStorageValue: %v", err)
	}
	leaf := rlp.EncodeList(rlp.EncodeBytes(compactEncode(true, nibbles(path[:]))), rlp.EncodeBytes(storedValue))
	root := keccak256.Sum256(leaf)
	return root, [][]byte{leaf}
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
