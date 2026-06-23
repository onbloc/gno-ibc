package ics23mpt

import (
	"bytes"
	"encoding/hex"
	"strings"
	"testing"
)

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
	value := ClientState{
		L2ChainID:         "11155111",
		L1ClientID:        1,
		L2ClientID:        1,
		L2LatestHeight:    8271613,
		TimestampOffset:   0xFFFF,
		StateRootOffset:   0xFFFF,
		StorageRootOffset: 0xFFFF,
	}
	want := mustClientStateWithOffsets(0xFFFF, 0xFFFF, 0xFFFF)

	got, err := EncodeClientState(value)
	if err != nil {
		t.Fatalf("EncodeClientState: %v", err)
	}
	assertBytes(t, "EncodeClientState", got, want)
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
	if _, err := DecodeClientState(mustClientStateWithLatestHeightWord(highPaddingWord(1))); err == nil {
		t.Fatalf("DecodeClientState accepted uint64 overflow")
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

func assertBytes(t *testing.T, name string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: got %x want %x", name, got, want)
	}
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic("mustHex: " + err.Error())
	}
	return bz
}

func word32(v uint64) string {
	out := make([]byte, 32)
	out[24] = byte(v >> 56)
	out[25] = byte(v >> 48)
	out[26] = byte(v >> 40)
	out[27] = byte(v >> 32)
	out[28] = byte(v >> 24)
	out[29] = byte(v >> 16)
	out[30] = byte(v >> 8)
	out[31] = byte(v)
	return hex.EncodeToString(out)
}

func mustClientStateWithOffsets(timestampOffset, stateRootOffset, storageRootOffset uint64) []byte {
	return mustHex(
		word32(0xe0) +
			word32(1) +
			word32(1) +
			word32(0x7e36fd) +
			word32(timestampOffset) +
			word32(stateRootOffset) +
			word32(storageRootOffset) +
			word32(8) +
			"3131313535313131000000000000000000000000000000000000000000000000",
	)
}

func mustClientStateWithIDs(l1ClientID, l2ClientID uint64) []byte {
	return mustHex(
		word32(0xe0) +
			word32(l1ClientID) +
			word32(l2ClientID) +
			word32(0x7e36fd) +
			word32(0x78) +
			word32(0x20) +
			word32(0x40) +
			word32(8) +
			"3131313535313131000000000000000000000000000000000000000000000000",
	)
}

func mustClientStateWithLatestHeightWord(l2LatestHeight string) []byte {
	return mustHex(
		word32(0xe0) +
			word32(1) +
			word32(1) +
			l2LatestHeight +
			word32(0x78) +
			word32(0x20) +
			word32(0x40) +
			word32(8) +
			"3131313535313131000000000000000000000000000000000000000000000000",
	)
}

func mustConsensusStateBytes(timestamp uint64, stateRoot, storageRoot []byte) []byte {
	return mustHex(
		word32(timestamp) +
			hex.EncodeToString(stateRoot) +
			hex.EncodeToString(storageRoot),
	)
}

func mustHeaderBytes(
	l1Height string,
	l2Height string,
	l2ConsensusStateProofOffset string,
	l2ConsensusStateOffset string,
	l2ConsensusStateProofLength string,
	l2ConsensusStateProofData string,
	l2ConsensusStateLength string,
	l2ConsensusStateData string,
) []byte {
	return mustHex(
		l1Height +
			l2Height +
			l2ConsensusStateProofOffset +
			l2ConsensusStateOffset +
			l2ConsensusStateProofLength +
			paddedBytesHex(l2ConsensusStateProofData) +
			l2ConsensusStateLength +
			paddedBytesHex(l2ConsensusStateData),
	)
}

func highPaddingWord(v uint64) string {
	return "01" + strings.Repeat("00", 23) + word32(v)[48:]
}

func paddedBytesHex(s string) string {
	if len(s)%64 == 0 {
		return s
	}
	return s + strings.Repeat("0", 64-len(s)%64)
}
