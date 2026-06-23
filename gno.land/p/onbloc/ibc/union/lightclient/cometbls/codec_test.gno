package cometbls

import (
	"bytes"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestClientStateCodecRoundTrip(t *testing.T) {
	cs := &ClientState{
		ChainID:         "union-devnet-1",
		TrustingPeriod:  100,
		UnbondingPeriod: 200,
		MaxClockDrift:   30,
		FrozenHeight:    types.NewHeight(0),
		LatestHeight:    types.NewHeight(42),
		ContractAddress: H256(repeat32Arr(0xAB)),
	}

	bz, err := EncodeClientState(cs)
	if err != nil {
		t.Fatalf("EncodeClientState: %v", err)
	}
	got, err := DecodeClientState(bz)
	if err != nil {
		t.Fatalf("DecodeClientState: %v", err)
	}
	if got.ChainID != cs.ChainID ||
		got.TrustingPeriod != cs.TrustingPeriod ||
		got.UnbondingPeriod != cs.UnbondingPeriod ||
		got.MaxClockDrift != cs.MaxClockDrift ||
		!got.FrozenHeight.EQ(cs.FrozenHeight) ||
		!got.LatestHeight.EQ(cs.LatestHeight) ||
		got.ContractAddress != cs.ContractAddress {
		t.Fatalf("client state round-trip mismatch: got %#v want %#v", got, cs)
	}
}

func TestConsensusStateCodecRoundTrip(t *testing.T) {
	cs := &ConsensusState{
		Timestamp:          1234567890,
		Root:               MerkleRoot{Hash: repeat32(0xCD)},
		NextValidatorsHash: repeat32(0xEF),
	}

	bz, err := EncodeConsensusState(cs)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	got, err := DecodeConsensusState(bz)
	if err != nil {
		t.Fatalf("DecodeConsensusState: %v", err)
	}
	if got.Timestamp != cs.Timestamp ||
		!bytes.Equal(got.Root.Hash, cs.Root.Hash) ||
		!bytes.Equal(got.NextValidatorsHash, cs.NextValidatorsHash) {
		t.Fatalf("consensus state round-trip mismatch: got %#v want %#v", got, cs)
	}
}

func repeat32Arr(b byte) [32]byte {
	var out [32]byte
	for i := range out {
		out[i] = b
	}
	return out
}

// TestEncodeClientStateNil covers the nil input branch.
func TestEncodeClientStateNil(t *testing.T) {
	_, err := EncodeClientState(nil)
	if err == nil || !contains(err.Error(), "nil client state") {
		t.Fatalf("expected error containing 'nil client state', got %v", err)
	}
}

// TestEncodeConsensusStateNil covers the nil input branch.
func TestEncodeConsensusStateNil(t *testing.T) {
	_, err := EncodeConsensusState(nil)
	if err == nil || !contains(err.Error(), "nil consensus state") {
		t.Fatalf("expected error containing 'nil consensus state', got %v", err)
	}
}

// TestDecodeClientStateMalformed covers truncated/invalid ABI input.
func TestDecodeClientStateMalformed(t *testing.T) {
	cases := []struct {
		name    string
		data    []byte
		wantErr string
	}{
		{
			name:    "empty buffer",
			data:    []byte{},
			wantErr: "abi",
		},
		{
			name:    "too short",
			data:    make([]byte, 100),
			wantErr: "abi",
		},
		{
			name: "truncated after first field",
			data: func() []byte {
				// ChainID field only (partial encoding)
				buf := make([]byte, 32+32)
				buf[32] = 't' // some bytes for chainid
				return buf
			}(),
			wantErr: "abi",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := DecodeClientState(tc.data)
			if err == nil || !contains(err.Error(), tc.wantErr) {
				t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
			}
		})
	}
}

// TestDecodeConsensusStateMalformed covers truncated/invalid ABI input.
func TestDecodeConsensusStateMalformed(t *testing.T) {
	cases := []struct {
		name    string
		data    []byte
		wantErr string
	}{
		{
			name:    "empty buffer",
			data:    []byte{},
			wantErr: "abi",
		},
		{
			name:    "too short",
			data:    make([]byte, 31),
			wantErr: "abi",
		},
		{
			name: "truncated timestamp field",
			data: func() []byte {
				// Only 32 bytes of timestamp instead of 96 bytes total
				buf := make([]byte, 32)
				buf[31] = 0x01
				return buf
			}(),
			wantErr: "abi",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := DecodeConsensusState(tc.data)
			if err == nil || !contains(err.Error(), tc.wantErr) {
				t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
			}
		})
	}
}

// TestBytes32Slice verifies that bytes32Slice returns an independent copy
// and correctly converts a [32]byte to []byte.
func TestBytes32Slice(t *testing.T) {
	cases := []struct {
		name  string
		input [32]byte
		want  []byte
	}{
		{
			name:  "all zeros",
			input: [32]byte{},
			want:  make([]byte, 32),
		},
		{
			name:  "pattern 0xAA",
			input: repeat32Arr(0xAA),
			want:  repeat32(0xAA),
		},
		{
			name: "mixed pattern",
			input: func() [32]byte {
				var out [32]byte
				for i := range out {
					out[i] = byte(i)
				}
				return out
			}(),
			want: func() []byte {
				out := make([]byte, 32)
				for i := range out {
					out[i] = byte(i)
				}
				return out
			}(),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := bytes32Slice(tc.input)
			if !bytes.Equal(got, tc.want) {
				t.Fatalf("bytes32Slice: got %x want %x", got, tc.want)
			}
			// Verify the output is a copy, not an alias
			got[0] ^= 0xFF
			if tc.input[0] == got[0] {
				t.Fatal("bytes32Slice returned aliased slice; modification affected input")
			}
		})
	}
}
