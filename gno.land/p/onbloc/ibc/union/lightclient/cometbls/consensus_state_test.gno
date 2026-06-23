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

func TestConsensusStateGetters(t *testing.T) {
	root := MerkleRoot{Hash: repeat32(0xAB)}
	nvh := repeat32(0xCD)
	cs := NewConsensusState(testNow, root, nvh)

	if cs.GetTimestamp() != testNow {
		t.Errorf("GetTimestamp: got %d want %d", cs.GetTimestamp(), testNow)
	}
	bytesEq(t, "GetRoot", cs.GetRoot().Hash, root.Hash)
	bytesEq(t, "GetNextValidatorsHash", cs.GetNextValidatorsHash(), nvh)
	if cs.ClientType() != ClientType {
		t.Errorf("ClientType: got %q want %q", cs.ClientType(), ClientType)
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
