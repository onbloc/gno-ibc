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
	c, err := NewStateLensIcs23MptLightClient(cs, cons, l1)
	if err != nil {
		t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
	}
	return c
}

func TestClientAccessors(t *testing.T) {
	c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))

	tests := []struct {
		name string
		kind string
	}{
		{name: "latest height", kind: "height"},
		{name: "counterparty chain id", kind: "chain-id"},
		{name: "latest timestamp", kind: "timestamp"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			switch tt.kind {
			case "height":
				if got := c.GetLatestHeight(); got != 10 {
					t.Errorf("GetLatestHeight: got %d want 10", got)
				}
			case "chain-id":
				if got := c.GetCounterpartyChainID(); got != "l2-chain" {
					t.Errorf("GetCounterpartyChainID: got %q want l2-chain", got)
				}
			case "timestamp":
				if got := c.GetTimestamp(); got != types.Timestamp(12345) {
					t.Errorf("GetTimestamp: got %d want 12345", got)
				}
			}
		})
	}
}

func TestClientGetTimestampNoConsensus(t *testing.T) {
	tests := []struct {
		name         string
		latestHeight Height
		want         types.Timestamp
	}{
		{name: "missing latest consensus state", latestHeight: 999, want: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			c.clientState.L2LatestHeight = tt.latestHeight
			if got := c.GetTimestamp(); got != tt.want {
				t.Errorf("GetTimestamp: got %d want %d", got, tt.want)
			}
		})
	}
}

func TestStatusMirrorsL1(t *testing.T) {
	cases := []struct {
		name string
		l1   lightclient.Status
		want lightclient.Status
	}{
		{name: "active", l1: lightclient.Active, want: lightclient.Active},
		{name: "expired", l1: lightclient.Expired, want: lightclient.Expired},
		{name: "frozen", l1: lightclient.Frozen, want: lightclient.Frozen},
		{name: "unknown maps to frozen", l1: lightclient.Unknown, want: lightclient.Frozen},
		{name: "unauthorized maps to frozen", l1: lightclient.Unauthorized, want: lightclient.Frozen},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: tc.l1}, bytes.Repeat([]byte{0x02}, 32))
			if got := c.Status(); got != tc.want {
				t.Errorf("Status with L1=%q: got %q want %q", tc.l1, got, tc.want)
			}
		})
	}
}

func TestStatusNilL1IsFrozen(t *testing.T) {
	tests := []struct {
		name string
		want lightclient.Status
	}{
		{name: "nil l1 client is frozen", want: lightclient.Frozen},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cs := &ClientState{L2ChainID: "l2", L2LatestHeight: 1}
			cons := &ConsensusState{Timestamp: 1, StateRoot: bytes.Repeat([]byte{0x01}, 32), StorageRoot: bytes.Repeat([]byte{0x02}, 32)}
			c, err := NewStateLensIcs23MptLightClient(cs, cons, nil)
			if err != nil {
				t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
			}
			if got := c.Status(); got != tt.want {
				t.Errorf("Status with nil L1: got %q want %q", got, tt.want)
			}
		})
	}
}

func TestVerifyHeaderUpdatesState(t *testing.T) {
	tests := []struct {
		name             string
		header           Header
		wantLatestHeight Height
		wantClientBytes  bool
		wantTimestamp    uint64
	}{
		{
			name: "valid header advances latest height",
			header: Header{
				L1Height:              20,
				L2Height:              11,
				L2ConsensusStateProof: []byte("l1-proof"),
				L2ConsensusState:      makeConsensusBytes(67890, bytes.Repeat([]byte{0xcc}, 32), bytes.Repeat([]byte{0xdd}, 32)),
			},
			wantLatestHeight: 11,
			wantClientBytes:  true,
			wantTimestamp:    67890,
		},
		{
			name: "valid older header stores consensus without advancing latest height",
			header: Header{
				L1Height:              21,
				L2Height:              9,
				L2ConsensusStateProof: []byte("old-l1-proof"),
				L2ConsensusState:      makeConsensusBytes(45678, bytes.Repeat([]byte{0xcc}, 32), bytes.Repeat([]byte{0xdd}, 32)),
			},
			wantLatestHeight: 10,
			wantTimestamp:    45678,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l1 := &mockL1Client{status: lightclient.Active}
			c := newTestClient(t, l1, bytes.Repeat([]byte{0x02}, 32))

			headerBytes, err := EncodeHeader(tt.header)
			if err != nil {
				t.Fatalf("EncodeHeader: %v", err)
			}

			var caller, relayer address
			update, err := c.VerifyHeader(caller, headerBytes, relayer)
			if err != nil {
				t.Fatalf("VerifyHeader: %v", err)
			}
			if update.Height != tt.header.L2Height {
				t.Errorf("update height: got %d want %d", update.Height, tt.header.L2Height)
			}
			if (len(update.ClientStateBytes) != 0) != tt.wantClientBytes {
				t.Errorf("client state bytes present: got %t want %t", len(update.ClientStateBytes) != 0, tt.wantClientBytes)
			}

			// The L1 membership check must target the L2 consensus-state path at L1Height
			// with the keccak256 of the L2 consensus blob.
			if !l1.called {
				t.Fatal("expected L1 VerifyMembership to be called")
			}
			if l1.gotHeight != tt.header.L1Height {
				t.Errorf("L1 height: got %d want %d", l1.gotHeight, tt.header.L1Height)
			}
			wantPath := types.ConsensusStatePath(types.ClientId(7), types.NewHeight(tt.header.L2Height))
			if !bytes.Equal(l1.gotKey, wantPath[:]) {
				t.Errorf("L1 key mismatch")
			}
			if !bytes.Equal(l1.gotProof, tt.header.L2ConsensusStateProof) {
				t.Errorf("L1 proof mismatch")
			}
			wantHash := keccak256.Sum256(tt.header.L2ConsensusState)
			if !bytes.Equal(l1.gotValue, wantHash[:]) {
				t.Errorf("L1 value mismatch")
			}

			// The extracted consensus state must be stored and the latest height advanced.
			if c.GetLatestHeight() != tt.wantLatestHeight {
				t.Errorf("latest height: got %d want %d", c.GetLatestHeight(), tt.wantLatestHeight)
			}
			got, found := c.getConsensusState(tt.header.L2Height)
			if !found {
				t.Fatalf("consensus state at height %d not stored", tt.header.L2Height)
			}
			if got.Timestamp != tt.wantTimestamp ||
				!bytes.Equal(got.StateRoot, bytes.Repeat([]byte{0xcc}, 32)) ||
				!bytes.Equal(got.StorageRoot, bytes.Repeat([]byte{0xdd}, 32)) {
				t.Fatalf("unexpected extracted consensus state: %#v", got)
			}
		})
	}
}

func TestVerifyHeaderRejectsWhenL1Fails(t *testing.T) {
	tests := []struct {
		name   string
		header Header
	}{
		{
			name: "membership verification failure",
			header: Header{
				L1Height:              20,
				L2Height:              11,
				L2ConsensusStateProof: []byte("l1-proof"),
				L2ConsensusState:      makeConsensusBytes(1, bytes.Repeat([]byte{0xcc}, 32), bytes.Repeat([]byte{0xdd}, 32)),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l1 := &mockL1Client{status: lightclient.Active, membershipErr: errors.New("boom")}
			c := newTestClient(t, l1, bytes.Repeat([]byte{0x02}, 32))

			headerBytes, err := EncodeHeader(tt.header)
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
		})
	}
}

func TestVerifyHeaderNilL1(t *testing.T) {
	tests := []struct {
		name    string
		header  []byte
		wantErr error
	}{
		{name: "nil l1 client", header: []byte{0x00}, wantErr: ErrNoL1Client},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cs := &ClientState{L2ChainID: "l2", L2ClientID: 7, L2LatestHeight: 10, StorageRootOffset: 32}
			cons := &ConsensusState{Timestamp: 1, StateRoot: bytes.Repeat([]byte{0x01}, 32), StorageRoot: bytes.Repeat([]byte{0x02}, 32)}
			c, err := NewStateLensIcs23MptLightClient(cs, cons, nil)
			if err != nil {
				t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
			}
			var caller, relayer address
			if _, err := c.VerifyHeader(caller, tt.header, relayer); err != tt.wantErr {
				t.Fatalf("VerifyHeader nil L1: got %v want %v", err, tt.wantErr)
			}
		})
	}
}

func TestUpdateState(t *testing.T) {
	tests := []struct {
		name              string
		initialHeight     Height
		headerHeight      Height
		wantLatestHeight  Height
		wantClientBytes   bool
		wantConsensusTime uint64
	}{
		{name: "newer header advances latest height", initialHeight: 10, headerHeight: 11, wantLatestHeight: 11, wantClientBytes: true, wantConsensusTime: 67890},
		{name: "older header stores consensus without advancing latest height", initialHeight: 10, headerHeight: 9, wantLatestHeight: 10, wantConsensusTime: 67890},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			c.clientState.L2LatestHeight = tt.initialHeight
			cons := &ConsensusState{
				Timestamp:   tt.wantConsensusTime,
				StateRoot:   bytes.Repeat([]byte{0xcc}, 32),
				StorageRoot: bytes.Repeat([]byte{0xdd}, 32),
			}

			update := c.updateState(Header{L2Height: tt.headerHeight}, cons)
			if update.Height != tt.headerHeight {
				t.Fatalf("update height: got %d want %d", update.Height, tt.headerHeight)
			}
			if c.GetLatestHeight() != tt.wantLatestHeight {
				t.Fatalf("latest height: got %d want %d", c.GetLatestHeight(), tt.wantLatestHeight)
			}
			if (len(update.ClientStateBytes) != 0) != tt.wantClientBytes {
				t.Fatalf("client state bytes present: got %t want %t", len(update.ClientStateBytes) != 0, tt.wantClientBytes)
			}
			if len(update.ConsensusStateBytes) == 0 {
				t.Fatalf("expected consensus state bytes")
			}
			got, found := c.getConsensusState(tt.headerHeight)
			if !found {
				t.Fatalf("consensus state at height %d not stored", tt.headerHeight)
			}
			if got.Timestamp != tt.wantConsensusTime ||
				!bytes.Equal(got.StateRoot, cons.StateRoot) ||
				!bytes.Equal(got.StorageRoot, cons.StorageRoot) {
				t.Fatalf("stored consensus state: got %#v want %#v", got, cons)
			}
		})
	}
}

func TestMisbehaviourUnsupported(t *testing.T) {
	tests := []struct {
		name         string
		misbehaviour []byte
		wantErr      error
	}{
		{name: "unsupported misbehaviour", misbehaviour: nil, wantErr: ErrMisbehaviourUnsupported},
		{name: "unsupported non-empty misbehaviour", misbehaviour: []byte{0x01, 0x02}, wantErr: ErrMisbehaviourUnsupported},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			var caller, relayer address
			if _, err := c.Misbehaviour(caller, tt.misbehaviour, relayer); err != tt.wantErr {
				t.Fatalf("Misbehaviour: got %v want %v", err, tt.wantErr)
			}
		})
	}
}

func TestVerifyCreationEmpty(t *testing.T) {
	tests := []struct {
		name string
	}{
		{name: "empty creation result"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			var caller, relayer address
			res, err := c.VerifyCreation(caller, relayer)
			if err != nil {
				t.Fatalf("VerifyCreation: %v", err)
			}
			if len(res.ClientStateBytes) != 0 {
				t.Errorf("VerifyCreation must not write a client state")
			}
		})
	}
}

func TestVerifyMembershipStorageProof(t *testing.T) {
	tests := []struct {
		name        string
		path        []byte
		value       []byte
		corruptRoot bool
		wantErr     bool
	}{
		{name: "valid storage proof", path: bytes.Repeat([]byte{0x11}, 32), value: storage.WordFromUint64(0xdeadbeef)},
		{name: "storage proof rejected for wrong root", path: bytes.Repeat([]byte{0x11}, 32), value: storage.WordFromUint64(0xdeadbeef), corruptRoot: true, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			slot, err := storage.IBCCommitmentKey(tt.path)
			if err != nil {
				t.Fatalf("IBCCommitmentKey: %v", err)
			}
			root, nodes := storageProofFixture(t, slot[:], tt.value)
			if tt.corruptRoot {
				root[0] ^= 0xff
			}

			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, root[:])

			proof := storage.EncodeProof(storage.Proof{
				Key:   slot[:],
				Value: tt.value,
				Proof: nodes,
			})
			err = c.VerifyMembership(10, tt.path, proof, tt.value)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("VerifyMembership accepted invalid storage proof")
				}
				return
			}
			if err != nil {
				t.Fatalf("VerifyMembership: %v", err)
			}
		})
	}
}

func TestVerifyMembershipRejectsValueMismatch(t *testing.T) {
	tests := []struct {
		name    string
		path    []byte
		stored  []byte
		value   []byte
		wantErr error
	}{
		{name: "stored value mismatch", path: bytes.Repeat([]byte{0x11}, 32), stored: storage.WordFromUint64(0xdeadbeef), value: storage.WordFromUint64(0xcafe), wantErr: ErrStoredValueMismatch},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			slot, err := storage.IBCCommitmentKey(tt.path)
			if err != nil {
				t.Fatalf("IBCCommitmentKey: %v", err)
			}
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			proof := storage.EncodeProof(storage.Proof{
				Key:   slot[:],
				Value: tt.stored,
			})
			if err := c.VerifyMembership(10, tt.path, proof, tt.value); err != tt.wantErr {
				t.Fatalf("VerifyMembership: got %v want %v", err, tt.wantErr)
			}
		})
	}
}

func TestVerifyMembershipRejectsNon32Value(t *testing.T) {
	tests := []struct {
		name    string
		path    []byte
		value   []byte
		wantErr error
	}{
		{name: "non-32-byte value", path: bytes.Repeat([]byte{0x11}, 32), value: []byte{0x01}, wantErr: ErrInvalidCommitmentValue},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			slot, err := storage.IBCCommitmentKey(tt.path)
			if err != nil {
				t.Fatalf("IBCCommitmentKey: %v", err)
			}
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			proof := storage.EncodeProof(storage.Proof{
				Key:   slot[:],
				Value: make([]byte, 32),
			})
			if err := c.VerifyMembership(10, tt.path, proof, tt.value); err != tt.wantErr {
				t.Fatalf("VerifyMembership: got %v want %v", err, tt.wantErr)
			}
		})
	}
}

func TestVerifyNonMembershipStorageProof(t *testing.T) {
	tests := []struct {
		name    string
		path    []byte
		present bool
		wantErr bool
	}{
		{name: "valid empty storage proof", path: bytes.Repeat([]byte{0x22}, 32)},
		{name: "present key rejected", path: bytes.Repeat([]byte{0x22}, 32), present: true, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			slot, err := storage.IBCCommitmentKey(tt.path)
			if err != nil {
				t.Fatalf("IBCCommitmentKey: %v", err)
			}
			root := keccak256.Sum256(rlp.EncodeBytes(nil))
			var nodes [][]byte
			if tt.present {
				value := storage.WordFromUint64(0x1234)
				root, nodes = storageProofFixture(t, slot[:], value)
			}

			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, root[:])
			proof := storage.EncodeProof(storage.Proof{
				Key:   slot[:],
				Value: make([]byte, 32),
				Proof: nodes,
			})
			err = c.VerifyNonMembership(10, tt.path, proof)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("VerifyNonMembership accepted present key")
				}
				return
			}
			if err != nil {
				t.Fatalf("VerifyNonMembership: %v", err)
			}
		})
	}
}

func TestPrepareProof(t *testing.T) {
	path := bytes.Repeat([]byte{0x11}, 32)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}
	validProof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: storage.WordFromUint64(0xdeadbeef),
	})

	tests := []struct {
		name    string
		height  uint64
		key     []byte
		proof   []byte
		wantErr error
		anyErr  bool
	}{
		{name: "success", height: 10, key: path, proof: validProof},
		{name: "height too high", height: 11, key: path, proof: validProof, wantErr: ErrInvalidHeight},
		{name: "consensus not found", height: 5, key: path, proof: validProof, wantErr: ErrConsensusStateNotFound},
		{name: "invalid storage proof", height: 10, key: path, proof: []byte{0xff}, anyErr: true},
		{name: "wrong commitment key", height: 10, key: path, proof: storage.EncodeProof(storage.Proof{
			Key:   storage.WordFromUint64(2),
			Value: storage.WordFromUint64(0xdeadbeef),
		}), wantErr: ErrInvalidCommitmentKey},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			consensusState, storageProof, err := c.prepareProof(tt.height, tt.key, tt.proof)
			if tt.anyErr {
				if err == nil {
					t.Fatalf("prepareProof accepted invalid input")
				}
				return
			}
			if err != tt.wantErr {
				t.Fatalf("prepareProof: got %v want %v", err, tt.wantErr)
			}
			if err != nil {
				return
			}
			if consensusState.Timestamp != 12345 {
				t.Fatalf("consensus timestamp: got %d want 12345", consensusState.Timestamp)
			}
			assertBytes(t, "storage proof key", storageProof.Key, slot[:])
		})
	}
}

func TestGetConsensusState(t *testing.T) {
	tests := []struct {
		name string
		kind string
	}{
		{name: "missing height", kind: "missing"},
		{name: "stored consensus state", kind: "stored"},
		{name: "wrong stored type", kind: "wrong-type"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			switch tt.kind {
			case "missing":
				if _, found := c.getConsensusState(9); found {
					t.Fatalf("getConsensusState found missing height")
				}
			case "stored":
				cons := &ConsensusState{Timestamp: 99, StateRoot: bytes.Repeat([]byte{0x03}, 32), StorageRoot: bytes.Repeat([]byte{0x04}, 32)}
				c.setConsensusState(9, cons)
				got, found := c.getConsensusState(9)
				if !found {
					t.Fatalf("getConsensusState did not find stored height")
				}
				if got != cons {
					t.Fatalf("getConsensusState returned unexpected pointer")
				}
			case "wrong-type":
				// Injecting a non-*ConsensusState value should return (nil, false).
				c.consensusStateByHeight.Set(heightKey(8), "not a consensus state")
				got, found := c.getConsensusState(8)
				if found {
					t.Fatalf("getConsensusState found non-*ConsensusState value")
				}
				if got != nil {
					t.Fatalf("getConsensusState returned non-nil for wrong type")
				}
			}
		})
	}
}

func TestHeightKey(t *testing.T) {
	tests := []struct {
		name   string
		height Height
		want   string
	}{
		{"zero height", 0, "00000000000000000000-00000000000000000000"},
		{"simple height", 1, "00000000000000000000-00000000000000000001"},
		{"height 10", 10, "00000000000000000000-00000000000000000010"},
		{"height 100", 100, "00000000000000000000-00000000000000000100"},
		{"large height", 1234567890, "00000000000000000000-00000000001234567890"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := heightKey(tt.height); got != tt.want {
				t.Fatalf("heightKey: got %q want %q", got, tt.want)
			}
		})
	}
}

func TestNewStateLensIcs23MptLightClient(t *testing.T) {
	tests := []struct {
		name string
		cs   *ClientState
		cons *ConsensusState
	}{
		{
			name: "stores initial consensus state",
			cs: &ClientState{
				L2ChainID:         "l2-chain",
				L1ClientID:        1,
				L2ClientID:        7,
				L2LatestHeight:    10,
				TimestampOffset:   64,
				StateRootOffset:   0,
				StorageRootOffset: 32,
			},
			cons: &ConsensusState{
				Timestamp:   12345,
				StateRoot:   bytes.Repeat([]byte{0xaa}, 32),
				StorageRoot: bytes.Repeat([]byte{0x02}, 32),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l1 := &mockL1Client{status: lightclient.Active}
			c, err := NewStateLensIcs23MptLightClient(tt.cs, tt.cons, l1)
			if err != nil {
				t.Fatalf("NewStateLensIcs23MptLightClient: %v", err)
			}

			// The initial consensus state must be stored at L2LatestHeight.
			got, found := c.getConsensusState(tt.cs.L2LatestHeight)
			if !found {
				t.Fatal("initial consensus state not stored at L2LatestHeight")
			}
			if got.Timestamp != tt.cons.Timestamp {
				t.Errorf("timestamp: got %d want %d", got.Timestamp, tt.cons.Timestamp)
			}
			if !bytes.Equal(got.StateRoot, tt.cons.StateRoot) {
				t.Errorf("state root mismatch")
			}
			if !bytes.Equal(got.StorageRoot, tt.cons.StorageRoot) {
				t.Errorf("storage root mismatch")
			}
		})
	}
}

func TestVerifyHeaderRejectsMalformedHeader(t *testing.T) {
	tests := []struct {
		name   string
		header []byte
	}{
		{name: "invalid ABI bytes", header: []byte{0xff, 0xff, 0xff}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l1 := &mockL1Client{status: lightclient.Active}
			c := newTestClient(t, l1, bytes.Repeat([]byte{0x02}, 32))

			// Invalid ABI bytes should fail decode without calling L1 membership.
			var caller, relayer address
			_, err := c.VerifyHeader(caller, tt.header, relayer)
			if err == nil {
				t.Fatal("expected VerifyHeader to fail with malformed header")
			}

			// Ensure L1 membership was not called.
			if l1.called {
				t.Fatal("L1 VerifyMembership should not be called for malformed header")
			}
		})
	}
}

func TestGetTimestampAtHeight(t *testing.T) {
	tests := []struct {
		name    string
		height  uint64
		want    types.Timestamp
		wantErr error
	}{
		{name: "existing height", height: 10, want: types.Timestamp(12345)},
		{name: "missing height", height: 5, wantErr: ErrConsensusStateNotFound},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestClient(t, &mockL1Client{status: lightclient.Active}, bytes.Repeat([]byte{0x02}, 32))
			ts, err := c.GetTimestampAtHeight(tt.height)
			if err != tt.wantErr {
				t.Fatalf("GetTimestampAtHeight(%d): got error %v want %v", tt.height, err, tt.wantErr)
			}
			if err != nil {
				return
			}
			if ts != tt.want {
				t.Errorf("timestamp: got %d want %d", ts, tt.want)
			}
		})
	}
}
