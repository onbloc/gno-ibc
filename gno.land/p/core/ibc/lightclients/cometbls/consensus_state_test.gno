package cometbls

import (
	"bytes"
	"testing"
)

func TestEncodeConsensusState(cur realm, t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		cs := ConsensusState{
			Timestamp:          500,
			Root:               MerkleRoot{Hash: bytes.Repeat([]byte{0xAB}, 32)},
			NextValidatorsHash: repeatH256(0xCD),
		}
		want := mustHex(word32(500) + bytes32hex(0xAB) + bytes32hex(0xCD))
		got, err := EncodeConsensusState(cs)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		bytesEq(t, "EncodeConsensusState/basic", got, want)
	})

	t.Run("invalid_root_hash", func(t *testing.T) {
		cs := ConsensusState{
			Timestamp:          1,
			Root:               MerkleRoot{Hash: []byte{0x01}},
			NextValidatorsHash: repeatH256(0xFF),
		}
		_, err := EncodeConsensusState(cs)
		if err == nil {
			t.Fatal("expected error for non-32-byte root hash")
		}
	})
}

func TestDecodeConsensusState(cur realm, t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		buf := mustHex(word32(500) + bytes32hex(0xAB) + bytes32hex(0xCD))
		got, err := DecodeConsensusState(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.Timestamp != 500 {
			t.Fatalf("Timestamp: got %d want 500", got.Timestamp)
		}
		bytesEq(t, "Root.Hash", got.Root.Hash, bytes.Repeat([]byte{0xAB}, 32))
		wantNVH := repeatH256(0xCD)
		if got.NextValidatorsHash != wantNVH {
			t.Fatalf("NextValidatorsHash: got %x want %x", got.NextValidatorsHash[:], wantNVH[:])
		}
	})

	t.Run("too_short", func(t *testing.T) {
		_, err := DecodeConsensusState(make([]byte, 63))
		if err == nil {
			t.Fatal("expected error for short buffer")
		}
	})
}

func TestEncodeDecodeConsensusStateRoundTrip(cur realm, t *testing.T) {
	original := ConsensusState{
		Timestamp:          123456789,
		Root:               MerkleRoot{Hash: bytes.Repeat([]byte{0xAA}, 32)},
		NextValidatorsHash: repeatH256(0xBB),
	}
	enc, err := EncodeConsensusState(original)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	got, err := DecodeConsensusState(enc)
	if err != nil {
		t.Fatalf("DecodeConsensusState: %v", err)
	}
	if got.Timestamp != original.Timestamp {
		t.Fatalf("Timestamp: got %d want %d", got.Timestamp, original.Timestamp)
	}
	bytesEq(t, "Root.Hash", got.Root.Hash, original.Root.Hash)
	if got.NextValidatorsHash != original.NextValidatorsHash {
		t.Fatalf("NextValidatorsHash: got %x want %x", got.NextValidatorsHash[:], original.NextValidatorsHash[:])
	}
}
