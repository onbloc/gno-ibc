package cometbls

import (
	"bytes"
	"testing"
)

func chainIdWord(s string) string {
	out := make([]byte, 32)
	copy(out, []byte(s))
	b := make([]byte, 0, 64)
	for _, v := range out {
		b = append(b, "0123456789abcdef"[v>>4], "0123456789abcdef"[v&0xf])
	}
	return string(b)
}

func TestEncodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		cs := ClientState{
			ChainID:        "abc",
			TrustingPeriod: 1000,
			MaxClockDrift:  100,
		}
		want := mustHex(
			chainIdWord("abc") +
				word32(1000) +
				word32(100) +
				word32(0) +
				word32(0) +
				bytes32hex(0x00),
		)
		got, err := EncodeClientState(cs)
		if err != nil {
			t.Fatalf("EncodeClientState: %v", err)
		}
		bytesEq(t, "EncodeClientState/basic", got, want)
	})

	t.Run("with_heights", func(t *testing.T) {
		var contractAddress [32]byte
		copy(contractAddress[:], bytes.Repeat([]byte{0xAB}, 32))
		cs := ClientState{
			ChainID:         "chain",
			TrustingPeriod:  100,
			MaxClockDrift:   10,
			FrozenHeight:    1,
			LatestHeight:    999,
			ContractAddress: contractAddress,
		}
		want := mustHex(
			chainIdWord("chain") +
				word32(100) +
				word32(10) +
				word32(1) +
				word32(999) +
				bytes32hex(0xAB),
		)
		got, err := EncodeClientState(cs)
		if err != nil {
			t.Fatalf("EncodeClientState: %v", err)
		}
		bytesEq(t, "EncodeClientState/with_heights", got, want)
	})
}

func TestDecodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		buf := mustHex(
			chainIdWord("abc") +
				word32(1000) +
				word32(100) +
				word32(0) +
				word32(50) +
				bytes32hex(0xCD),
		)
		got, err := DecodeClientState(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.ChainID != "abc" {
			t.Fatalf("ChainID: got %q want %q", got.ChainID, "abc")
		}
		if got.TrustingPeriod != 1000 {
			t.Fatalf("TrustingPeriod: got %d want 1000", got.TrustingPeriod)
		}
		if got.MaxClockDrift != 100 {
			t.Fatalf("MaxClockDrift: got %d want 100", got.MaxClockDrift)
		}
		if got.IsFrozen() {
			t.Fatal("FrozenHeight should be zero")
		}
		if got.LatestHeight != 50 {
			t.Fatalf("LatestHeight: got %d want 50", got.LatestHeight)
		}
		if !bytes.Equal(got.ContractAddress[:], bytes.Repeat([]byte{0xCD}, 32)) {
			t.Fatal("ContractAddress mismatch")
		}
	})

	t.Run("frozen", func(t *testing.T) {
		buf := mustHex(
			chainIdWord("x") +
				word32(100) +
				word32(10) +
				word32(1) +
				word32(99) +
				bytes32hex(0x00),
		)
		got, err := DecodeClientState(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !got.IsFrozen() {
			t.Fatal("expected FrozenHeight to be set")
		}
	})

	t.Run("too_short", func(t *testing.T) {
		_, err := DecodeClientState([]byte{0x00, 0x01, 0x02})
		if err == nil {
			t.Fatal("expected error for short buffer")
		}
	})
}

func TestEncodeDecodeClientStateRoundTrip(t *testing.T) {
	maxUint64 := ^uint64(0)
	testCases := []ClientState{
		{
			ContractAddress: repeatH256(0x00),
		},
		{
			ChainID:         "a",
			TrustingPeriod:  1,
			MaxClockDrift:   1,
			FrozenHeight:    1,
			LatestHeight:    1,
			ContractAddress: repeatH256(0x11),
		},
		{
			ChainID:         "union-devnet-1-padded-to-31byte",
			TrustingPeriod:  maxUint64,
			MaxClockDrift:   maxUint64,
			FrozenHeight:    0,
			LatestHeight:    maxUint64,
			ContractAddress: repeatH256(0xFF),
		},
		{
			ChainID:         "union-devnet-1",
			TrustingPeriod:  14 * 24 * 3600 * 1_000_000_000,
			MaxClockDrift:   10 * 1_000_000_000,
			FrozenHeight:    1,
			LatestHeight:    1337,
			ContractAddress: repeatH256(0xAB),
		},
	}

	for _, original := range testCases {
		encoded, err := EncodeClientState(original)
		if err != nil {
			t.Fatalf("EncodeClientState: %v", err)
		}
		got, err := DecodeClientState(encoded)
		if err != nil {
			t.Fatalf("DecodeClientState: %v", err)
		}
		if got != original {
			t.Fatalf("ClientState: got %#v want %#v", got, original)
		}
		if got.IsFrozen() != (original.FrozenHeight != 0) {
			t.Fatalf("IsFrozen: got %v want %v", got.IsFrozen(), original.FrozenHeight != 0)
		}
	}
}
