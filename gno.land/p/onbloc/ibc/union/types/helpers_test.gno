package types

import (
	"encoding/hex"
	"testing"
)

func assertHex(t *testing.T, name string, got []byte, want string) {
	t.Helper()

	if hex.EncodeToString(got) != want {
		t.Fatalf("%s: got %s want %s", name, hex.EncodeToString(got), want)
	}
}

func mustBytes(t *testing.T, h string) []byte {
	t.Helper()

	bz, err := hex.DecodeString(h)
	if err != nil {
		t.Fatalf("decode hex: %v", err)
	}

	return bz
}

func mustH256(t *testing.T, h string) H256 {
	t.Helper()

	bz := mustBytes(t, h)
	if len(bz) != 32 {
		t.Fatalf("hex length: got %d want 32", len(bz))
	}

	var out H256
	copy(out[:], bz)
	return out
}
