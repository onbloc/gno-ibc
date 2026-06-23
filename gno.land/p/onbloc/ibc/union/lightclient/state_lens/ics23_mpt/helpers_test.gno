package ics23mpt

import (
	"bytes"
	"crypto/keccak256"
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/onbloc/encoding/rlp"
	"gno.land/p/onbloc/verifier/evm/storage"
)

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

func highPaddingWord(v uint64) string {
	return "01" + strings.Repeat("00", 23) + word32(v)[48:]
}

func paddedBytesHex(s string) string {
	if len(s)%64 == 0 {
		return s
	}
	return s + strings.Repeat("0", 64-len(s)%64)
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

// makeConsensusBytes lays out an L2 consensus blob matching the offsets used by
// newTestClient: state_root at 0, storage_root at 32, big-endian timestamp at
// 64.
func makeConsensusBytes(timestamp uint64, stateRoot, storageRoot []byte) []byte {
	out := make([]byte, 72)
	copy(out[0:32], stateRoot)
	copy(out[32:64], storageRoot)
	out[64] = byte(timestamp >> 56)
	out[65] = byte(timestamp >> 48)
	out[66] = byte(timestamp >> 40)
	out[67] = byte(timestamp >> 32)
	out[68] = byte(timestamp >> 24)
	out[69] = byte(timestamp >> 16)
	out[70] = byte(timestamp >> 8)
	out[71] = byte(timestamp)
	return out
}

// storageProofFixture builds a single-leaf MPT proving slot stores value, and
// returns its root and the proof node list. Mirrors the realm test fixture.
func storageProofFixture(t *testing.T, slot []byte, value []byte) ([32]byte, [][]byte) {
	t.Helper()
	path, err := storage.StoragePath(slot)
	if err != nil {
		t.Fatalf("StoragePath: %v", err)
	}
	storedValue, err := storage.EncodeStorageValue(value)
	if err != nil {
		t.Fatalf("EncodeStorageValue: %v", err)
	}
	leaf := rlp.EncodeList(rlp.EncodeBytes(compactEncode(true, nibbles(path[:]))), rlp.EncodeBytes(storedValue))
	root := keccak256.Sum256(leaf)
	return root, [][]byte{leaf}
}

func nibbles(key []byte) []byte {
	out := make([]byte, 0, len(key)*2)
	for _, b := range key {
		out = append(out, b>>4, b&0x0f)
	}
	return out
}

func compactEncode(leaf bool, ns []byte) []byte {
	flag := byte(0)
	if leaf {
		flag = 2
	}
	odd := len(ns)%2 == 1
	out := make([]byte, 0, (len(ns)+2)/2)
	if odd {
		out = append(out, (flag+1)<<4|ns[0])
		ns = ns[1:]
	} else {
		out = append(out, flag<<4)
	}
	for i := 0; i < len(ns); i += 2 {
		out = append(out, ns[i]<<4|ns[i+1])
	}
	return out
}
