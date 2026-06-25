package cometbls

import (
	"testing"
)

func TestConsensusStateValidateBasic(t *testing.T) {
	cases := []struct {
		name    string
		state   ConsensusState
		wantErr string
	}{
		{
			name: "valid",
			state: ConsensusState{
				Timestamp:          testNow,
				Root:               MerkleRoot{Hash: repeat32(0xAB)},
				NextValidatorsHash: repeat32(0xCD),
			},
		},
		{
			name:  "valid empty next validators hash",
			state: ConsensusState{Root: MerkleRoot{Hash: repeat32(0xAB)}},
		},
		{
			name:    "nil root",
			state:   ConsensusState{Root: MerkleRoot{Hash: nil}, NextValidatorsHash: repeat32(0xCD)},
			wantErr: "root hash",
		},
		{
			name:    "empty root",
			state:   ConsensusState{Root: MerkleRoot{Hash: []byte{}}, NextValidatorsHash: repeat32(0xCD)},
			wantErr: "root hash",
		},
		{
			name:    "bad next validators hash length",
			state:   ConsensusState{Root: MerkleRoot{Hash: repeat32(0xAB)}, NextValidatorsHash: []byte{0x01, 0x02}},
			wantErr: "next validators hash",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.state.ValidateBasic()
			if tc.wantErr == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			requireErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestNewConsensusState(t *testing.T) {
	cases := []struct {
		name               string
		timestamp          uint64
		root               MerkleRoot
		nextValidatorsHash []byte
		wantTimestamp      uint64
		wantRootHash       []byte
		wantNVH            []byte
	}{
		{
			name:               "valid all fields",
			timestamp:          testNow,
			root:               MerkleRoot{Hash: repeat32(0xAB)},
			nextValidatorsHash: repeat32(0xCD),
			wantTimestamp:      testNow,
			wantRootHash:       repeat32(0xAB),
			wantNVH:            repeat32(0xCD),
		},
		{
			name:               "zero timestamp",
			timestamp:          0,
			root:               MerkleRoot{Hash: repeat32(0xFF)},
			nextValidatorsHash: repeat32(0xEE),
			wantTimestamp:      0,
			wantRootHash:       repeat32(0xFF),
			wantNVH:            repeat32(0xEE),
		},
		{
			name:               "max timestamp",
			timestamp:          ^uint64(0),
			root:               MerkleRoot{Hash: repeat32(0x01)},
			nextValidatorsHash: repeat32(0x02),
			wantTimestamp:      ^uint64(0),
			wantRootHash:       repeat32(0x01),
			wantNVH:            repeat32(0x02),
		},
		{
			name:               "empty next validators hash",
			timestamp:          testNow,
			root:               MerkleRoot{Hash: repeat32(0xAB)},
			nextValidatorsHash: []byte{},
			wantTimestamp:      testNow,
			wantRootHash:       repeat32(0xAB),
			wantNVH:            []byte{},
		},
		{
			name:               "nil next validators hash",
			timestamp:          testNow,
			root:               MerkleRoot{Hash: repeat32(0xAB)},
			nextValidatorsHash: nil,
			wantTimestamp:      testNow,
			wantRootHash:       repeat32(0xAB),
			wantNVH:            nil,
		},
		{
			name:               "all zeros root",
			timestamp:          testNow,
			root:               MerkleRoot{Hash: repeat32(0x00)},
			nextValidatorsHash: repeat32(0x00),
			wantTimestamp:      testNow,
			wantRootHash:       repeat32(0x00),
			wantNVH:            repeat32(0x00),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := NewConsensusState(tc.timestamp, tc.root, tc.nextValidatorsHash)
			if got == nil {
				t.Fatalf("NewConsensusState: got nil want non-nil")
			}
			if got.Timestamp != tc.wantTimestamp {
				t.Errorf("Timestamp: got %d want %d", got.Timestamp, tc.wantTimestamp)
			}
			bytesEq(t, "Root", got.Root.Hash, tc.wantRootHash)
			if tc.wantNVH != nil {
				bytesEq(t, "NextValidatorsHash", got.NextValidatorsHash, tc.wantNVH)
			} else {
				if got.NextValidatorsHash != nil {
					t.Errorf("NextValidatorsHash: got non-nil want nil")
				}
			}
		})
	}
}

func TestConsensusStateGetters(t *testing.T) {
	cases := []struct {
		name               string
		timestamp          uint64
		root               MerkleRoot
		nextValidatorsHash []byte
		wantTimestamp      uint64
		wantClientType     string
	}{
		{
			name:               "valid basic",
			timestamp:          testNow,
			root:               MerkleRoot{Hash: repeat32(0xAB)},
			nextValidatorsHash: repeat32(0xCD),
			wantTimestamp:      testNow,
			wantClientType:     ClientType,
		},
		{
			name:               "zero timestamp",
			timestamp:          0,
			root:               MerkleRoot{Hash: repeat32(0xFF)},
			nextValidatorsHash: repeat32(0xEE),
			wantTimestamp:      0,
			wantClientType:     ClientType,
		},
		{
			name:               "max timestamp",
			timestamp:          ^uint64(0),
			root:               MerkleRoot{Hash: repeat32(0x01)},
			nextValidatorsHash: repeat32(0x02),
			wantTimestamp:      ^uint64(0),
			wantClientType:     ClientType,
		},
		{
			name:               "empty root hash",
			timestamp:          12345,
			root:               MerkleRoot{Hash: []byte{}},
			nextValidatorsHash: repeat32(0x03),
			wantTimestamp:      12345,
			wantClientType:     ClientType,
		},
		{
			name:               "nil next validators hash",
			timestamp:          9999,
			root:               MerkleRoot{Hash: repeat32(0xAA)},
			nextValidatorsHash: nil,
			wantTimestamp:      9999,
			wantClientType:     ClientType,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cs := NewConsensusState(tc.timestamp, tc.root, tc.nextValidatorsHash)

			if got := cs.GetTimestamp(); got != tc.wantTimestamp {
				t.Errorf("GetTimestamp: got %d want %d", got, tc.wantTimestamp)
			}
			bytesEq(t, "GetRoot", cs.GetRoot().Hash, tc.root.Hash)
			if got := cs.ClientType(); got != tc.wantClientType {
				t.Errorf("ClientType: got %q want %q", got, tc.wantClientType)
			}
			if tc.nextValidatorsHash != nil {
				bytesEq(t, "GetNextValidatorsHash", cs.GetNextValidatorsHash(), tc.nextValidatorsHash)
			} else {
				if cs.GetNextValidatorsHash() != nil {
					t.Errorf("GetNextValidatorsHash: got non-nil want nil")
				}
			}
		})
	}
}

func TestMerkleRootEmpty(t *testing.T) {
	cases := []struct {
		name string
		root MerkleRoot
		want bool
	}{
		{"zero root", MerkleRoot{}, true},
		{"non-empty root", MerkleRoot{Hash: repeat32(0x01)}, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.root.Empty(); got != tc.want {
				t.Fatalf("Empty: got %v want %v", got, tc.want)
			}
		})
	}
}
