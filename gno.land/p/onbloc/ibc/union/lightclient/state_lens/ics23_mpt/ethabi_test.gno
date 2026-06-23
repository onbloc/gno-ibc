package ics23mpt

import (
	"bytes"
	"encoding/hex"
	"testing"
)

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

func TestDecodeClientStateOffsetBoundaries(t *testing.T) {
	tests := []struct {
		name    string
		offsets []uint64
		want    ClientState
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
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			bz := mustClientStateWithOffsets(tt.offsets[0], tt.offsets[1], tt.offsets[2])
			got, err := DecodeClientState(bz)
			if err != nil {
				t.Fatalf("DecodeClientState: %v", err)
			}
			if got != tt.want {
				t.Fatalf("DecodeClientState: got %#v want %#v", got, tt.want)
			}
		})
	}
}

func TestEncodeClientStateMaxOffsets(t *testing.T) {
	tests := []struct {
		name  string
		value ClientState
		want  []byte
	}{
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

func TestRejectInvalidClientStateOffsets(t *testing.T) {
	tests := []struct {
		name    string
		offsets []uint64
	}{
		{name: "timestamp offset", offsets: []uint64{0x10000, 0x20, 0x40}},
		{name: "state root offset", offsets: []uint64{0x10, 0x10000, 0x40}},
		{name: "storage root offset", offsets: []uint64{0x10, 0x20, 0x10000}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			bz := mustClientStateWithOffsets(tt.offsets[0], tt.offsets[1], tt.offsets[2])
			if _, err := DecodeClientState(bz); err == nil {
				t.Fatalf("DecodeClientState accepted uint16 overflow")
			}
		})
	}
}

func TestRejectInvalidClientStateUint32Fields(t *testing.T) {
	tests := []struct {
		name string
		bz   []byte
	}{
		{name: "l1 client id", bz: mustClientStateWithIDs(0x100000000, 1)},
		{name: "l2 client id", bz: mustClientStateWithIDs(1, 0x100000000)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := DecodeClientState(tt.bz); err == nil {
				t.Fatalf("DecodeClientState accepted uint32 overflow")
			}
		})
	}
}

func TestDecodeClientStateRejectsMalformedUint64Fields(t *testing.T) {
	tests := []struct {
		name string
		bz   []byte
	}{
		{name: "latest height high padding", bz: mustClientStateWithLatestHeightWord(highPaddingWord(1))},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := DecodeClientState(tt.bz); err == nil {
				t.Fatalf("DecodeClientState accepted uint64 overflow")
			}
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

func TestDecodeConsensusStateRejectsMalformedData(t *testing.T) {
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
