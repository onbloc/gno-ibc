package cometbls

import (
	"bytes"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestCodecRoundTrip(t *testing.T) {
	cases := []struct {
		name   string
		encode func(any) ([]byte, error)
		decode func([]byte) (any, error)
		input  any
		assert func(*testing.T, any, any)
	}{
		{
			name:   "client state",
			encode: func(v any) ([]byte, error) { return EncodeClientState(v.(*ClientState)) },
			decode: func(bz []byte) (any, error) { return DecodeClientState(bz) },
			input: &ClientState{
				ChainID:         "union-devnet-1",
				TrustingPeriod:  100,
				UnbondingPeriod: 200,
				MaxClockDrift:   30,
				FrozenHeight:    types.NewHeight(0),
				LatestHeight:    types.NewHeight(42),
				ContractAddress: H256(repeat32Arr(0xAB)),
			},
			assert: func(t *testing.T, got, want any) {
				g := got.(*ClientState)
				w := want.(*ClientState)
				if g.ChainID != w.ChainID ||
					g.TrustingPeriod != w.TrustingPeriod ||
					g.UnbondingPeriod != w.UnbondingPeriod ||
					g.MaxClockDrift != w.MaxClockDrift ||
					!g.FrozenHeight.EQ(w.FrozenHeight) ||
					!g.LatestHeight.EQ(w.LatestHeight) ||
					g.ContractAddress != w.ContractAddress {
					t.Fatalf("client state round-trip mismatch: got %#v want %#v", g, w)
				}
			},
		},
		{
			name:   "consensus state",
			encode: func(v any) ([]byte, error) { return EncodeConsensusState(v.(*ConsensusState)) },
			decode: func(bz []byte) (any, error) { return DecodeConsensusState(bz) },
			input: &ConsensusState{
				Timestamp:          1234567890,
				Root:               MerkleRoot{Hash: repeat32(0xCD)},
				NextValidatorsHash: repeat32(0xEF),
			},
			assert: func(t *testing.T, got, want any) {
				g := got.(*ConsensusState)
				w := want.(*ConsensusState)
				if g.Timestamp != w.Timestamp ||
					!bytes.Equal(g.Root.Hash, w.Root.Hash) ||
					!bytes.Equal(g.NextValidatorsHash, w.NextValidatorsHash) {
					t.Fatalf("consensus state round-trip mismatch: got %#v want %#v", g, w)
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			bz, err := tc.encode(tc.input)
			if err != nil {
				t.Fatalf("encode: %v", err)
			}
			got, err := tc.decode(bz)
			if err != nil {
				t.Fatalf("decode: %v", err)
			}
			tc.assert(t, got, tc.input)
		})
	}
}

func TestEncodeNil(t *testing.T) {
	cases := []struct {
		name      string
		encode    func() ([]byte, error)
		wantErr   string
	}{
		{
			name: "client state",
			encode: func() ([]byte, error) {
				return EncodeClientState(nil)
			},
			wantErr: "nil client state",
		},
		{
			name: "consensus state",
			encode: func() ([]byte, error) {
				return EncodeConsensusState(nil)
			},
			wantErr: "nil consensus state",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := tc.encode()
			if err == nil || !contains(err.Error(), tc.wantErr) {
				t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
			}
		})
	}
}

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

func repeat32Arr(b byte) [32]byte {
	var out [32]byte
	for i := range out {
		out[i] = b
	}
	return out
}
