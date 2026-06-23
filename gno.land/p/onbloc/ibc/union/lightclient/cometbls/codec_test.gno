package cometbls

import (
	"bytes"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestEncodeClientState(t *testing.T) {
	cases := []struct {
		name    string
		input   *ClientState
		wantErr string
		assert  func(*testing.T, []byte, *ClientState)
	}{
		{
			name: "valid client state",
			input: &ClientState{
				ChainID:         "union-devnet-1",
				TrustingPeriod:  100,
				UnbondingPeriod: 200,
				MaxClockDrift:   30,
				FrozenHeight:    types.NewHeight(0),
				LatestHeight:    types.NewHeight(42),
				ContractAddress: H256(repeat32Arr(0xAB)),
			},
			wantErr: "",
			assert: func(t *testing.T, got []byte, cs *ClientState) {
				// Verify non-empty output
				if len(got) == 0 {
					t.Fatal("encoded output is empty")
				}
				// ClientState schema has 7 fields, output should be non-trivial
				if len(got) < 64 {
					t.Fatalf("encoded output too short: got %d bytes", len(got))
				}
			},
		},
		{
			name: "zero values",
			input: &ClientState{
				ChainID:         "",
				TrustingPeriod:  0,
				UnbondingPeriod: 0,
				MaxClockDrift:   0,
				FrozenHeight:    types.NewHeight(0),
				LatestHeight:    types.NewHeight(0),
				ContractAddress: H256{},
			},
			wantErr: "",
			assert: func(t *testing.T, got []byte, cs *ClientState) {
				if len(got) == 0 {
					t.Fatal("encoded output is empty")
				}
			},
		},
		{
			name: "max values",
			input: &ClientState{
				ChainID:         "max-chain",
				TrustingPeriod:  ^uint64(0),
				UnbondingPeriod: ^uint64(0),
				MaxClockDrift:   ^uint64(0),
				FrozenHeight:    types.NewHeight(^uint64(0)),
				LatestHeight:    types.NewHeight(^uint64(0)),
				ContractAddress: H256(repeat32Arr(0xFF)),
			},
			wantErr: "",
			assert: func(t *testing.T, got []byte, cs *ClientState) {
				if len(got) == 0 {
					t.Fatal("encoded output is empty")
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := EncodeClientState(tc.input)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.assert != nil {
				tc.assert(t, got, tc.input)
			}
		})
	}
}

func TestDecodeClientState(t *testing.T) {
	cases := []struct {
		name    string
		encode  func() (*ClientState, []byte, error)
		data    []byte
		wantErr string
		assert  func(*testing.T, *ClientState)
	}{
		{
			name: "valid encoded client state",
			encode: func() (*ClientState, []byte, error) {
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
				return cs, bz, err
			},
			wantErr: "",
			assert: func(t *testing.T, got *ClientState) {
				want := &ClientState{
					ChainID:         "union-devnet-1",
					TrustingPeriod:  100,
					UnbondingPeriod: 200,
					MaxClockDrift:   30,
					FrozenHeight:    types.NewHeight(0),
					LatestHeight:    types.NewHeight(42),
					ContractAddress: H256(repeat32Arr(0xAB)),
				}
				if got.ChainID != want.ChainID ||
					got.TrustingPeriod != want.TrustingPeriod ||
					got.UnbondingPeriod != want.UnbondingPeriod ||
					got.MaxClockDrift != want.MaxClockDrift ||
					!got.FrozenHeight.EQ(want.FrozenHeight) ||
					!got.LatestHeight.EQ(want.LatestHeight) ||
					got.ContractAddress != want.ContractAddress {
					t.Fatalf("decoded mismatch: got %#v want %#v", got, want)
				}
			},
		},
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
				buf := make([]byte, 32+32)
				buf[32] = 't'
				return buf
			}(),
			wantErr: "abi",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var data []byte
			if tc.data != nil {
				data = tc.data
			} else if tc.encode != nil {
				_, data, _ = tc.encode()
			}

			got, err := DecodeClientState(data)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.assert != nil {
				tc.assert(t, got)
			}
		})
	}
}

func TestClientStateReverseTransform(t *testing.T) {
	cases := []struct {
		name  string
		input *ClientState
	}{
		{
			name: "valid client state",
			input: &ClientState{
				ChainID:         "union-devnet-1",
				TrustingPeriod:  100,
				UnbondingPeriod: 200,
				MaxClockDrift:   30,
				FrozenHeight:    types.NewHeight(0),
				LatestHeight:    types.NewHeight(42),
				ContractAddress: H256(repeat32Arr(0xAB)),
			},
		},
		{
			name: "zero values",
			input: &ClientState{
				ChainID:         "",
				TrustingPeriod:  0,
				UnbondingPeriod: 0,
				MaxClockDrift:   0,
				FrozenHeight:    types.NewHeight(0),
				LatestHeight:    types.NewHeight(0),
				ContractAddress: H256{},
			},
		},
		{
			name: "max values",
			input: &ClientState{
				ChainID:         "max-chain",
				TrustingPeriod:  ^uint64(0),
				UnbondingPeriod: ^uint64(0),
				MaxClockDrift:   ^uint64(0),
				FrozenHeight:    types.NewHeight(^uint64(0)),
				LatestHeight:    types.NewHeight(^uint64(0)),
				ContractAddress: H256(repeat32Arr(0xFF)),
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			// Forward: encode
			encoded, err := EncodeClientState(tc.input)
			if err != nil {
				t.Fatalf("encode: %v", err)
			}

			// Reverse: decode
			decoded, err := DecodeClientState(encoded)
			if err != nil {
				t.Fatalf("decode: %v", err)
			}

			// Verify reverse transform (encode decoded → compare with original encoded)
			reEncoded, err := EncodeClientState(decoded)
			if err != nil {
				t.Fatalf("re-encode: %v", err)
			}

			if !bytes.Equal(encoded, reEncoded) {
				t.Fatalf("reverse transform mismatch:\noriginal: %x\nre-encoded: %x", encoded, reEncoded)
			}

			// Final: verify decoded matches original
			if decoded.ChainID != tc.input.ChainID ||
				decoded.TrustingPeriod != tc.input.TrustingPeriod ||
				decoded.UnbondingPeriod != tc.input.UnbondingPeriod ||
				decoded.MaxClockDrift != tc.input.MaxClockDrift ||
				!decoded.FrozenHeight.EQ(tc.input.FrozenHeight) ||
				!decoded.LatestHeight.EQ(tc.input.LatestHeight) ||
				decoded.ContractAddress != tc.input.ContractAddress {
				t.Fatalf("round-trip mismatch:\ngot      %#v\noriginal %#v", decoded, tc.input)
			}
		})
	}
}

func TestEncodeConsensusState(t *testing.T) {
	cases := []struct {
		name    string
		input   *ConsensusState
		wantErr string
		assert  func(*testing.T, []byte, *ConsensusState)
	}{
		{
			name: "valid consensus state",
			input: &ConsensusState{
				Timestamp:          1234567890,
				Root:               MerkleRoot{Hash: repeat32(0xCD)},
				NextValidatorsHash: repeat32(0xEF),
			},
			wantErr: "",
			assert: func(t *testing.T, got []byte, cs *ConsensusState) {
				if len(got) == 0 {
					t.Fatal("encoded output is empty")
				}
				// ConsensusState schema has 3 fields (64 bytes each)
				if len(got) < 96 {
					t.Fatalf("encoded output too short: got %d bytes", len(got))
				}
			},
		},
		{
			name: "zero values",
			input: &ConsensusState{
				Timestamp:          0,
				Root:               MerkleRoot{Hash: make([]byte, 32)},
				NextValidatorsHash: make([]byte, 32),
			},
			wantErr: "",
			assert: func(t *testing.T, got []byte, cs *ConsensusState) {
				if len(got) == 0 {
					t.Fatal("encoded output is empty")
				}
			},
		},
		{
			name: "max timestamp",
			input: &ConsensusState{
				Timestamp:          ^uint64(0),
				Root:               MerkleRoot{Hash: repeat32(0xFF)},
				NextValidatorsHash: repeat32(0xFF),
			},
			wantErr: "",
			assert: func(t *testing.T, got []byte, cs *ConsensusState) {
				if len(got) == 0 {
					t.Fatal("encoded output is empty")
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := EncodeConsensusState(tc.input)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.assert != nil {
				tc.assert(t, got, tc.input)
			}
		})
	}
}

func TestDecodeConsensusState(t *testing.T) {
	cases := []struct {
		name    string
		encode  func() (*ConsensusState, []byte, error)
		data    []byte
		wantErr string
		assert  func(*testing.T, *ConsensusState)
	}{
		{
			name: "valid encoded consensus state",
			encode: func() (*ConsensusState, []byte, error) {
				cs := &ConsensusState{
					Timestamp:          1234567890,
					Root:               MerkleRoot{Hash: repeat32(0xCD)},
					NextValidatorsHash: repeat32(0xEF),
				}
				bz, err := EncodeConsensusState(cs)
				return cs, bz, err
			},
			wantErr: "",
			assert: func(t *testing.T, got *ConsensusState) {
				want := &ConsensusState{
					Timestamp:          1234567890,
					Root:               MerkleRoot{Hash: repeat32(0xCD)},
					NextValidatorsHash: repeat32(0xEF),
				}
				if got.Timestamp != want.Timestamp ||
					!bytes.Equal(got.Root.Hash, want.Root.Hash) ||
					!bytes.Equal(got.NextValidatorsHash, want.NextValidatorsHash) {
					t.Fatalf("decoded mismatch: got %#v want %#v", got, want)
				}
			},
		},
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
				buf := make([]byte, 32)
				buf[31] = 0x01
				return buf
			}(),
			wantErr: "abi",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var data []byte
			if tc.data != nil {
				data = tc.data
			} else if tc.encode != nil {
				_, data, _ = tc.encode()
			}

			got, err := DecodeConsensusState(data)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.assert != nil {
				tc.assert(t, got)
			}
		})
	}
}

func TestConsensusStateReverseTransform(t *testing.T) {
	cases := []struct {
		name  string
		input *ConsensusState
	}{
		{
			name: "valid consensus state",
			input: &ConsensusState{
				Timestamp:          1234567890,
				Root:               MerkleRoot{Hash: repeat32(0xCD)},
				NextValidatorsHash: repeat32(0xEF),
			},
		},
		{
			name: "zero values",
			input: &ConsensusState{
				Timestamp:          0,
				Root:               MerkleRoot{Hash: make([]byte, 32)},
				NextValidatorsHash: make([]byte, 32),
			},
		},
		{
			name: "max values",
			input: &ConsensusState{
				Timestamp:          ^uint64(0),
				Root:               MerkleRoot{Hash: repeat32(0xFF)},
				NextValidatorsHash: repeat32(0xFF),
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			// Forward: encode
			encoded, err := EncodeConsensusState(tc.input)
			if err != nil {
				t.Fatalf("encode: %v", err)
			}

			// Reverse: decode
			decoded, err := DecodeConsensusState(encoded)
			if err != nil {
				t.Fatalf("decode: %v", err)
			}

			// Verify reverse transform (encode decoded → compare with original encoded)
			reEncoded, err := EncodeConsensusState(decoded)
			if err != nil {
				t.Fatalf("re-encode: %v", err)
			}

			if !bytes.Equal(encoded, reEncoded) {
				t.Fatalf("reverse transform mismatch:\noriginal: %x\nre-encoded: %x", encoded, reEncoded)
			}

			// Final: verify decoded matches original
			if decoded.Timestamp != tc.input.Timestamp ||
				!bytes.Equal(decoded.Root.Hash, tc.input.Root.Hash) ||
				!bytes.Equal(decoded.NextValidatorsHash, tc.input.NextValidatorsHash) {
				t.Fatalf("round-trip mismatch:\ngot      %#v\noriginal %#v", decoded, tc.input)
			}
		})
	}
}

func TestEncodeNil(t *testing.T) {
	cases := []struct {
		name    string
		encode  func() ([]byte, error)
		wantErr string
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
