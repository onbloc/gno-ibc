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

func TestEncodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		cs := ClientState{
			ChainID:        "abc",
			TrustingPeriod: 1000,
			MaxClockDrift:  100,
		}
		want := mustHex("0a0361626310e8072064820120" + bytes32hex(0x00))
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
		want := mustHex("0a05636861696e1064200a2a021001320310e707820120" + bytes32hex(0xAB))
		bytesEq(t, "EncodeClientState/with_heights", EncodeClientState(cs), want)
	})

	t.Run("chain_id_64_bytes", func(t *testing.T) {
		id := string(bytes.Repeat([]byte{'x'}, 64))
		cs := ClientState{ChainID: id}
		got := EncodeClientState(cs)
		decoded, err := DecodeClientState(got)
		if err != nil {
			t.Fatalf("DecodeClientState: %v", err)
		}
		if decoded.ChainID != id {
			t.Fatalf("ChainID: got %q want %q", decoded.ChainID, id)
		}
	})
}

func TestDecodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		buf := mustHex("0a0361626310e807206432021032820120" + bytes32hex(0xCD))
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
		buf := mustHex("0a01781064200a2a02100132021063820120" + bytes32hex(0x00))
		got, err := DecodeClientState(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !got.IsFrozen() {
			t.Fatal("expected FrozenHeight to be set")
		}
	})

	t.Run("unknown_tag_skipped", func(t *testing.T) {
		buf := mustHex("0a0178a20103aabbcc820120" + bytes32hex(0x00))
		got, err := DecodeClientState(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.ChainID != "x" {
			t.Fatalf("ChainID: got %q want x", got.ChainID)
		}
	})

	t.Run("contract_address_absent_defaults_zero", func(t *testing.T) {
		got, err := DecodeClientState(mustHex("0a0178"))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.ContractAddress != (H256{}) {
			t.Fatalf("ContractAddress: got %x want zero", got.ContractAddress[:])
		}
	})

	t.Run("too_short", func(t *testing.T) {
		_, err := DecodeClientState([]byte{0x0a, 0x02, 0x01})
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
			ChainID:         string(bytes.Repeat([]byte{'x'}, 32)),
			TrustingPeriod:  maxUint64,
			MaxClockDrift:   maxUint64,
			FrozenHeight:    0,
			LatestHeight:    maxUint64,
			ContractAddress: repeatH256(0xFF),
		},
		{
			ChainID:         string(bytes.Repeat([]byte{'y'}, 64)),
			TrustingPeriod:  14 * 24 * 3600 * 1_000_000_000,
			MaxClockDrift:   10 * 1_000_000_000,
			FrozenHeight:    1,
			LatestHeight:    1337,
			ContractAddress: repeatH256(0xAB),
		},
		{
			ChainID:         string(bytes.Repeat([]byte{'z'}, 128)),
			TrustingPeriod:  0,
			MaxClockDrift:   0,
			FrozenHeight:    0,
			LatestHeight:    0,
			ContractAddress: repeatH256(0xCD),
		},
	}

	for _, original := range testCases {
		got, err := DecodeClientState(EncodeClientState(original))
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
