package cometbls

import (
	"testing"
)

func TestConsensusStateValidateBasic(t *testing.T) {
	t.Run("valid", func(t *testing.T) {
		cs := ConsensusState{
			Timestamp:          testNow,
			Root:               MerkleRoot{Hash: repeat32(0xAB)},
			NextValidatorsHash: repeat32(0xCD),
		}
		if err := cs.ValidateBasic(); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	})

	t.Run("valid_empty_next_validators_hash", func(t *testing.T) {
		// validateHash permits an empty hash (proto3 default).
		cs := ConsensusState{Root: MerkleRoot{Hash: repeat32(0xAB)}}
		if err := cs.ValidateBasic(); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	})

	t.Run("nil_root", func(t *testing.T) {
		cs := ConsensusState{Root: MerkleRoot{Hash: nil}, NextValidatorsHash: repeat32(0xCD)}
		if err := cs.ValidateBasic(); err == nil {
			t.Fatal("expected error for nil root hash")
		}
	})

	t.Run("empty_root", func(t *testing.T) {
		cs := ConsensusState{Root: MerkleRoot{Hash: []byte{}}, NextValidatorsHash: repeat32(0xCD)}
		if err := cs.ValidateBasic(); err == nil {
			t.Fatal("expected error for empty root hash")
		}
	})

	t.Run("bad_next_validators_hash_length", func(t *testing.T) {
		cs := ConsensusState{Root: MerkleRoot{Hash: repeat32(0xAB)}, NextValidatorsHash: []byte{0x01, 0x02}}
		if err := cs.ValidateBasic(); err == nil {
			t.Fatal("expected error for non-32-byte next validators hash")
		}
	})
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
	if !(MerkleRoot{}).Empty() {
		t.Error("zero MerkleRoot should be empty")
	}
	if (MerkleRoot{Hash: repeat32(0x01)}).Empty() {
		t.Error("non-empty MerkleRoot should not be empty")
	}
}
