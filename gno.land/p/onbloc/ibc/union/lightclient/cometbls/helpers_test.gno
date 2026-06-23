package cometbls

import (
	"bytes"
	"encoding/hex"
	"testing"
)

// testNow is 2024-01-01 00:00:00 UTC in nanoseconds, used as a fixed clock for
// tests that need a concrete timestamp.
const testNow = uint64(1_704_067_200) * 1_000_000_000

func bytesEq(t *testing.T, label string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: got %x want %x", label, got, want)
	}
}

// repeatBytes returns an n-byte slice with every byte set to b.
func repeatBytes(b byte, n int) []byte {
	return bytes.Repeat([]byte{b}, n)
}

// repeat32 returns a 32-byte slice with every byte set to b.
func repeat32(b byte) []byte {
	return repeatBytes(b, 32)
}

func mustHex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic("mustHex: " + err.Error())
	}
	return b
}

// word32 renders v as a big-endian 32-byte EVM word in hex.
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

// bytes32hex renders a 32-byte word with every byte set to b, in hex.
func bytes32hex(b byte) string {
	return hex.EncodeToString(bytes.Repeat([]byte{b}, 32))
}

func cloneTestHeaderWith(malleate func(*Header)) *Header {
	h := newTestHeader(1, 100, 0, 0, repeat32(0xFF))
	malleate(h)
	return h
}

func cloneLightHeaderWith(h *LightHeader, mutate func(*LightHeader)) *LightHeader {
	out := cloneLightHeader(h)
	mutate(out)
	return out
}

func cloneLightHeader(h *LightHeader) *LightHeader {
	if h == nil {
		return nil
	}
	return &LightHeader{
		Height:             h.Height,
		TimeSeconds:        h.TimeSeconds,
		TimeNanos:          h.TimeNanos,
		ValidatorsHash:     append([]byte(nil), h.ValidatorsHash...),
		NextValidatorsHash: append([]byte(nil), h.NextValidatorsHash...),
		AppHash:            append([]byte(nil), h.AppHash...),
	}
}

// contains reports whether substr is in s. Used by tests that cannot use strings.Contains.
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) && indexOf(s, substr) >= 0)
}

// indexOf returns the index of substr in s, or -1 if not found.
func indexOf(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
