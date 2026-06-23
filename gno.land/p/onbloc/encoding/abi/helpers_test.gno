package abi

import (
	"encoding/hex"
	"testing"
)

func assertError(t *testing.T, got, want error) {
	if got != want {
		t.Fatalf("error = %v, want %v", got, want)
	}
}

func assertHex(t *testing.T, name string, got []byte, want string) {
	if hex.EncodeToString(got) != want {
		t.Fatalf("%s\n got %s\nwant %s", name, hex.EncodeToString(got), want)
	}
}

func filledBytes(n int, value byte) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = value
	}
	return out
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}
