package storage

import (
	"encoding/hex"
	"testing"

	"crypto/keccak256"
	"gno.land/p/onbloc/encoding/rlp"
)

func bytesRepeat(b byte, n int) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = b
	}
	return out
}

func bytesEqual(a []byte, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func mustEncode(t *testing.T, word []byte) []byte {
	t.Helper()
	out, err := EncodeStorageValue(word)
	if err != nil {
		t.Fatalf("EncodeStorageValue: %v", err)
	}
	return out
}

func ethereumMappingBytes32Slot0(path []byte) [32]byte {
	var input [64]byte
	copy(input[0:32], path)
	return keccak256.Sum256(input[:])
}

func wordWithLastByte(b byte) []byte {
	out := make([]byte, 32)
	out[31] = b
	return out
}

func node(path []byte, valueOrRef []byte) []byte {
	return rlp.EncodeList(rlp.EncodeBytes(path), valueOrRef)
}

func hash(encoded []byte) [32]byte {
	return keccak256.Sum256(encoded)
}

func mptEmptyRoot() []byte {
	root := keccak256.Sum256(rlp.EncodeBytes(nil))
	return root[:]
}

func nibbles(key []byte) []byte {
	out := make([]byte, 0, len(key)*2)
	for _, b := range key {
		out = append(out, b>>4, b&0x0f)
	}
	return out
}

func leafPath(ns []byte) []byte {
	return compactEncode(true, ns)
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

func assertHex(t *testing.T, name string, got []byte, want string) {
	t.Helper()
	if hex.EncodeToString(got) != want {
		t.Fatalf("%s: got %x want %s", name, got, want)
	}
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}
