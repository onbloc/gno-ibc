package ics23mpt

import (
	"bytes"
	"encoding/hex"
	"testing"
)

func TestRejectInvalidClientStateOffsets(t *testing.T) {
	bz := mustHex(
		"00000000000000000000000000000000000000000000000000000000000000e0" +
			"0000000000000000000000000000000000000000000000000000000000000001" +
			"0000000000000000000000000000000000000000000000000000000000000001" +
			"00000000000000000000000000000000000000000000000000000000007e36fd" +
			"0000000000000000000000000000000000000000000000000000000000010000" +
			"0000000000000000000000000000000000000000000000000000000000000020" +
			"0000000000000000000000000000000000000000000000000000000000000040" +
			"0000000000000000000000000000000000000000000000000000000000000008" +
			"3131313535313131000000000000000000000000000000000000000000000000",
	)
	if _, err := DecodeClientState(bz); err == nil {
		t.Fatalf("DecodeClientState accepted uint16 overflow")
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
