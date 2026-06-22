package ics23mpt

import (
	"bytes"
	"encoding/hex"
	"testing"
)

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

func TestRejectInvalidConsensusStateRoots(t *testing.T) {
	_, err := EncodeConsensusState(ConsensusState{
		Timestamp:   1,
		StateRoot:   []byte{1},
		StorageRoot: bytes.Repeat([]byte{2}, 32),
	})
	if err == nil {
		t.Fatalf("EncodeConsensusState accepted invalid state root")
	}

	_, err = EncodeConsensusState(ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{1}, 32),
		StorageRoot: []byte{2},
	})
	if err == nil {
		t.Fatalf("EncodeConsensusState accepted invalid storage root")
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
