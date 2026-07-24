package ics23_mpt

import (
	"bytes"
	"encoding/hex"
	"testing"
)

func TestDecodeClientState(t *testing.T) {
	tests := []struct {
		name         string
		offsets      []uint64 // [timestamp, stateRoot, storageRoot]
		ids          []uint64 // [l1ClientID, l2ClientID]
		latestHeight string   // raw uint64 hex string for latest height
		want         ClientState
		wantErr      bool
	}{
		{
			name:    "zero offsets",
			offsets: []uint64{0, 0, 0},
			want: ClientState{
				L2ChainID:         "11155111",
				L1ClientID:        1,
				L2ClientID:        1,
				L2LatestHeight:    8271613,
				TimestampOffset:   0,
				StateRootOffset:   0,
				StorageRootOffset: 0,
			},
		},
		{
			name:    "max uint16 offsets",
			offsets: []uint64{0xFFFF, 0xFFFF, 0xFFFF},
			want: ClientState{
				L2ChainID:         "11155111",
				L1ClientID:        1,
				L2ClientID:        1,
				L2LatestHeight:    8271613,
				TimestampOffset:   0xFFFF,
				StateRootOffset:   0xFFFF,
				StorageRootOffset: 0xFFFF,
			},
		},
		{
			name:    "timestamp offset overflow",
			offsets: []uint64{0x10000, 0x20, 0x40},
			wantErr: true,
		},
		{
			name:    "state root offset overflow",
			offsets: []uint64{0x10, 0x10000, 0x40},
			wantErr: true,
		},
		{
			name:    "storage root offset overflow",
			offsets: []uint64{0x10, 0x20, 0x10000},
			wantErr: true,
		},
		{
			name:    "l1 client id overflow",
			ids:     []uint64{0x100000000, 1},
			wantErr: true,
		},
		{
			name:    "l2 client id overflow",
			ids:     []uint64{1, 0x100000000},
			wantErr: true,
		},
		{
			name:         "latest height high padding",
			latestHeight: highPaddingWord(1),
			wantErr:      true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var bz []byte

			if tt.ids != nil {
				bz = mustClientStateWithIDs(tt.ids[0], tt.ids[1])
			} else if tt.latestHeight != "" {
				bz = mustClientStateWithLatestHeightWord(tt.latestHeight)
			} else {
				bz = mustClientStateWithOffsets(tt.offsets[0], tt.offsets[1], tt.offsets[2])
			}

			got, err := DecodeClientState(bz)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("DecodeClientState accepted invalid input")
				}
				return
			}
			if err != nil {
				t.Fatalf("DecodeClientState: %v", err)
			}
			if got != tt.want {
				t.Fatalf("DecodeClientState: got %#v want %#v", got, tt.want)
			}
		})
	}
}

func TestEncodeClientState(t *testing.T) {
	tests := []struct {
		name  string
		value ClientState
		want  []byte
	}{
		{
			name: "zero offsets",
			value: ClientState{
				L2ChainID:         "11155111",
				L1ClientID:        1,
				L2ClientID:        1,
				L2LatestHeight:    8271613,
				TimestampOffset:   0,
				StateRootOffset:   0,
				StorageRootOffset: 0,
			},
			want: mustClientStateWithOffsets(0, 0, 0),
		},
		{
			name: "max uint16 offsets",
			value: ClientState{
				L2ChainID:         "11155111",
				L1ClientID:        1,
				L2ClientID:        1,
				L2LatestHeight:    8271613,
				TimestampOffset:   0xFFFF,
				StateRootOffset:   0xFFFF,
				StorageRootOffset: 0xFFFF,
			},
			want: mustClientStateWithOffsets(0xFFFF, 0xFFFF, 0xFFFF),
		},
		{
			name: "zero client ids",
			value: ClientState{
				L2ChainID:         "test-chain",
				L1ClientID:        0,
				L2ClientID:        0,
				L2LatestHeight:    100,
				TimestampOffset:   64,
				StateRootOffset:   0,
				StorageRootOffset: 32,
			},
			want: mustClientStateWithIDsAndOffsets(0, 0, 100, 64, 0, 32),
		},
		{
			name: "max uint32 client ids",
			value: ClientState{
				L2ChainID:         "test-chain",
				L1ClientID:        0xFFFFFFFF,
				L2ClientID:        0xFFFFFFFF,
				L2LatestHeight:    100,
				TimestampOffset:   64,
				StateRootOffset:   0,
				StorageRootOffset: 32,
			},
			want: mustClientStateWithIDsAndOffsets(0xFFFFFFFF, 0xFFFFFFFF, 100, 64, 0, 32),
		},
		{
			name: "zero latest height",
			value: ClientState{
				L2ChainID:         "test-chain",
				L1ClientID:        1,
				L2ClientID:        2,
				L2LatestHeight:    0,
				TimestampOffset:   128,
				StateRootOffset:   0,
				StorageRootOffset: 32,
			},
			want: mustClientStateWithHeightAndOffsets(0, 128, 0, 32),
		},
		{
			name: "max uint64 latest height",
			value: ClientState{
				L2ChainID:         "test-chain",
				L1ClientID:        1,
				L2ClientID:        2,
				L2LatestHeight:    0xFFFFFFFFFFFFFFFF,
				TimestampOffset:   64,
				StateRootOffset:   0,
				StorageRootOffset: 32,
			},
			want: mustClientStateWithHeightAndOffsets(0xFFFFFFFFFFFFFFFF, 64, 0, 32),
		},
		{
			name: "medium offsets",
			value: ClientState{
				L2ChainID:         "test-chain",
				L1ClientID:        5,
				L2ClientID:        10,
				L2LatestHeight:    9999,
				TimestampOffset:   128,
				StateRootOffset:   192,
				StorageRootOffset: 256,
			},
			want: mustClientStateWithIDsAndOffsets(5, 10, 9999, 128, 192, 256),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := EncodeClientState(tt.value)
			if err != nil {
				t.Fatalf("EncodeClientState: %v", err)
			}
			assertBytes(t, "EncodeClientState", got, tt.want)
		})
	}
}

func TestRejectInvalidConsensusStateRoots(t *testing.T) {
	tests := []struct {
		name string
		cs   ConsensusState
	}{
		{
			name: "nil state root",
			cs: ConsensusState{
				Timestamp:   1,
				StateRoot:   nil,
				StorageRoot: bytes.Repeat([]byte{2}, 32),
			},
		},
		{
			name: "short state root",
			cs: ConsensusState{
				Timestamp:   1,
				StateRoot:   bytes.Repeat([]byte{1}, 31),
				StorageRoot: bytes.Repeat([]byte{2}, 32),
			},
		},
		{
			name: "long state root",
			cs: ConsensusState{
				Timestamp:   1,
				StateRoot:   bytes.Repeat([]byte{1}, 33),
				StorageRoot: bytes.Repeat([]byte{2}, 32),
			},
		},
		{
			name: "nil storage root",
			cs: ConsensusState{
				Timestamp:   1,
				StateRoot:   bytes.Repeat([]byte{1}, 32),
				StorageRoot: nil,
			},
		},
		{
			name: "short storage root",
			cs: ConsensusState{
				Timestamp:   1,
				StateRoot:   bytes.Repeat([]byte{1}, 32),
				StorageRoot: bytes.Repeat([]byte{2}, 31),
			},
		},
		{
			name: "long storage root",
			cs: ConsensusState{
				Timestamp:   1,
				StateRoot:   bytes.Repeat([]byte{1}, 32),
				StorageRoot: bytes.Repeat([]byte{2}, 33),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := EncodeConsensusState(tt.cs); err == nil {
				t.Fatalf("EncodeConsensusState accepted invalid root")
			}
		})
	}
}

func TestDecodeConsensusState_RejectsMalformedData(t *testing.T) {
	valid := mustConsensusStateBytes(1, bytes.Repeat([]byte{1}, 32), bytes.Repeat([]byte{2}, 32))
	tests := []struct {
		name string
		bz   []byte
	}{
		{name: "short data", bz: valid[:len(valid)-1]},
		{name: "timestamp high padding", bz: mustHex(
			highPaddingWord(1) +
				hex.EncodeToString(bytes.Repeat([]byte{1}, 32)) +
				hex.EncodeToString(bytes.Repeat([]byte{2}, 32)),
		)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := DecodeConsensusState(tt.bz); err == nil {
				t.Fatalf("DecodeConsensusState accepted malformed data")
			}
		})
	}
}

func TestEncodeHeader(t *testing.T) {
	tests := []struct {
		name  string
		value Header
	}{
		{
			name: "basic header",
			value: Header{
				L1Height:              11,
				L2Height:              22,
				L2ConsensusStateProof: mustHex("aabbcc"),
				L2ConsensusState:      mustHex("01020304"),
			},
		},
		{
			name: "zero heights",
			value: Header{
				L1Height:              0,
				L2Height:              0,
				L2ConsensusStateProof: mustHex("aaaa"),
				L2ConsensusState:      mustHex("bbbb"),
			},
		},
		{
			name: "max uint64 heights",
			value: Header{
				L1Height:              0xFFFFFFFFFFFFFFFF,
				L2Height:              0xFFFFFFFFFFFFFFFF,
				L2ConsensusStateProof: mustHex("aabbcc"),
				L2ConsensusState:      mustHex("01020304"),
			},
		},
		{
			name: "empty proof and consensus state",
			value: Header{
				L1Height:              100,
				L2Height:              200,
				L2ConsensusStateProof: []byte{},
				L2ConsensusState:      []byte{},
			},
		},
		{
			name: "large proof and consensus state",
			value: Header{
				L1Height:              1000,
				L2Height:              2000,
				L2ConsensusStateProof: bytes.Repeat([]byte{0xAA}, 100),
				L2ConsensusState:      bytes.Repeat([]byte{0xBB}, 72),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Encode the header
			got, err := EncodeHeader(tt.value)
			if err != nil {
				t.Fatalf("EncodeHeader: %v", err)
			}

			// Verify round-trip: decode and re-encode must match
			decoded, err := DecodeHeader(got)
			if err != nil {
				t.Fatalf("DecodeHeader: %v", err)
			}
			if decoded.L1Height != tt.value.L1Height {
				t.Errorf("L1Height: got %d want %d", decoded.L1Height, tt.value.L1Height)
			}
			if decoded.L2Height != tt.value.L2Height {
				t.Errorf("L2Height: got %d want %d", decoded.L2Height, tt.value.L2Height)
			}
			assertBytes(t, "L2ConsensusStateProof", decoded.L2ConsensusStateProof, tt.value.L2ConsensusStateProof)
			assertBytes(t, "L2ConsensusState", decoded.L2ConsensusState, tt.value.L2ConsensusState)

			// Re-encode and verify match
			reenc, err := EncodeHeader(decoded)
			if err != nil {
				t.Fatalf("re-EncodeHeader: %v", err)
			}
			assertBytes(t, "round-trip", reenc, got)
		})
	}
}

func TestDecodeHeaderRejectsMalformedData(t *testing.T) {
	valid := mustHeaderBytes(
		word32(11),
		word32(22),
		word32(128),
		word32(192),
		word32(3),
		"aabbcc",
		word32(4),
		"01020304",
	)
	tests := []struct {
		name string
		bz   []byte
	}{
		{
			name: "l1 height high padding",
			bz: mustHeaderBytes(
				highPaddingWord(11),
				word32(22),
				word32(128),
				word32(192),
				word32(3),
				"aabbcc",
				word32(4),
				"01020304",
			),
		},
		{
			name: "l2 height high padding",
			bz: mustHeaderBytes(
				word32(11),
				highPaddingWord(22),
				word32(128),
				word32(192),
				word32(3),
				"aabbcc",
				word32(4),
				"01020304",
			),
		},
		{
			name: "proof offset unaligned",
			bz: mustHeaderBytes(
				word32(11),
				word32(22),
				word32(129),
				word32(192),
				word32(3),
				"aabbcc",
				word32(4),
				"01020304",
			),
		},
		{
			name: "consensus state length exceeds tail",
			bz: mustHeaderBytes(
				word32(11),
				word32(22),
				word32(128),
				word32(192),
				word32(3),
				"aabbcc",
				word32(33),
				"01020304",
			),
		},
		{name: "short data", bz: valid[:len(valid)-1]},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := DecodeHeader(tt.bz); err == nil {
				t.Fatalf("DecodeHeader accepted malformed data")
			}
		})
	}
}

func TestToUint16(t *testing.T) {
	tests := []struct {
		name    string
		value   uint32
		want    uint16
		wantErr bool
	}{
		{name: "zero", value: 0, want: 0},
		{name: "max uint16", value: 0xFFFF, want: 0xFFFF},
		{name: "overflow", value: 0x10000, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := toUint16(tt.value, "offset")
			if tt.wantErr {
				if err == nil {
					t.Fatalf("toUint16 accepted overflow")
				}
				return
			}
			if err != nil {
				t.Fatalf("toUint16: %v", err)
			}
			if got != tt.want {
				t.Fatalf("toUint16: got %d want %d", got, tt.want)
			}
		})
	}
}

func TestToBytes32(t *testing.T) {
	tests := []struct {
		name    string
		value   []byte
		wantErr bool
	}{
		{name: "bytes32", value: bytes.Repeat([]byte{0x01}, 32)},
		{name: "nil", value: nil, wantErr: true},
		{name: "short", value: bytes.Repeat([]byte{0x01}, 31), wantErr: true},
		{name: "long", value: bytes.Repeat([]byte{0x01}, 33), wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := toBytes32(tt.value, "root")
			if tt.wantErr {
				if err == nil {
					t.Fatalf("toBytes32 accepted invalid length")
				}
				return
			}
			if err != nil {
				t.Fatalf("toBytes32: %v", err)
			}
			assertBytes(t, "toBytes32", got[:], tt.value)
		})
	}
}

func TestCloneBytes(t *testing.T) {
	tests := []struct {
		name      string
		src       []byte
		want      []byte
		checkCopy bool
	}{
		{name: "copies non-empty slice", src: []byte{0x01, 0x02, 0x03}, want: []byte{0x01, 0x02, 0x03}, checkCopy: true},
		{name: "nil returns empty slice", src: nil, want: nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := cloneBytes(tt.src)
			assertBytes(t, "cloneBytes", got, tt.want)
			if tt.checkCopy {
				got[0] = 0xff
				if tt.src[0] != 0x01 {
					t.Fatalf("cloneBytes returned an aliased slice")
				}
			}
		})
	}
}
