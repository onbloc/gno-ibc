package cometbls

import (
	"bytes"
	"encoding/hex"
	"testing"
)

const wordSize = 32

func bytesEq(t *testing.T, label string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: got %x want %x", label, got, want)
	}
}

func repeatH256(b byte) H256 {
	var out H256
	for i := range out {
		out[i] = b
	}
	return out
}

func mustHex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic("mustHex: " + err.Error())
	}
	return b
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

func bytes32hex(b byte) string {
	return hex.EncodeToString(bytes.Repeat([]byte{b}, 32))
}

func chainIDWord32(s string) string {
	out := make([]byte, 32)
	copy(out, []byte(s))
	return hex.EncodeToString(out)
}

func TestEncodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		cs := ClientState{
			ChainID:        "abc",
			TrustingPeriod: 1000,
			MaxClockDrift:  100,
		}
		want := mustHex(
			chainIDWord32("abc") +
				word32(1000) +
				word32(100) +
				word32(0) +
				word32(0) +
				bytes32hex(0x00),
		)
		bytesEq(t, "EncodeClientState/basic", EncodeClientState(cs), want)
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
			chainIDWord32("chain") +
				word32(100) +
				word32(10) +
				word32(1) +
				word32(999) +
				bytes32hex(0xAB),
		)
		bytesEq(t, "EncodeClientState/with_heights", EncodeClientState(cs), want)
	})

	t.Run("chain_id_32_bytes", func(t *testing.T) {
		id := string(bytes.Repeat([]byte{'x'}, 32))
		cs := ClientState{ChainID: id}
		got := EncodeClientState(cs)
		if len(got) != 6*wordSize {
			t.Fatalf("want %d bytes got %d", 6*wordSize, len(got))
		}
		if string(got[:32]) != id {
			t.Fatalf("chain_id mismatch")
		}
	})
}

func TestDecodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		buf := mustHex(
			chainIDWord32("abc") +
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
			chainIDWord32("x") +
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
		_, err := DecodeClientState([]byte{0x01})
		if err == nil {
			t.Fatal("expected error for short buffer")
		}
	})
}

func TestEncodeDecodeClientStateRoundTrip(t *testing.T) {
	original := ClientState{
		ChainID:        "union-devnet-1337",
		TrustingPeriod: 14 * 24 * 3600 * 1_000_000_000,
		MaxClockDrift:  10 * 1_000_000_000,
		LatestHeight:   1337,
	}
	got, err := DecodeClientState(EncodeClientState(original))
	if err != nil {
		t.Fatalf("DecodeClientState: %v", err)
	}
	if got.ChainID != original.ChainID {
		t.Fatalf("ChainID: got %q want %q", got.ChainID, original.ChainID)
	}
	if got.TrustingPeriod != original.TrustingPeriod {
		t.Fatalf("TrustingPeriod: got %d want %d", got.TrustingPeriod, original.TrustingPeriod)
	}
	if got.MaxClockDrift != original.MaxClockDrift {
		t.Fatalf("MaxClockDrift: got %d want %d", got.MaxClockDrift, original.MaxClockDrift)
	}
	if got.LatestHeight != original.LatestHeight {
		t.Fatalf("LatestHeight: got %d want %d", got.LatestHeight, original.LatestHeight)
	}
}
