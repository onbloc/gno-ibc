package cometbls

import (
	"bytes"
	"testing"
)

func TestEncodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		cs := ClientState{
			ChainID:        "abc",
			TrustingPeriod: 1000,
			MaxClockDrift:  100,
		}
		// 0a 03 61 62 63        tag 1 (chain_id), len 3, "abc"
		// 10 e8 07              tag 2 (trusting_period), varint 1000
		// 20 64                 tag 4 (max_clock_drift), varint 100
		// 82 01 20 <32x00>      tag 16 (contract_address, Gno ext), len 32, all-zero
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
		// 0a 05 63 68 61 69 6e  tag 1 (chain_id), len 5, "chain"
		// 10 64                 tag 2 (trusting_period), varint 100
		// 20 0a                 tag 4 (max_clock_drift), varint 10
		// 2a 02 10 01           tag 5 (frozen_height submessage), inner tag 2 varint 1
		// 32 03 10 e7 07        tag 6 (latest_height submessage), inner tag 2 varint 999
		// 82 01 20 <32xAB>      tag 16 (contract_address, Gno ext), len 32
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

	t.Run("wrong_wire_type_on_known_field", func(t *testing.T) {
		// 0x12 = (field 2 << 3) | wireType 2; field 2 is TrustingPeriod
		// (varint, wire 0), so a length-delimited tag here must be rejected
		// instead of being silently mis-decoded as zero.
		_, err := DecodeClientState([]byte{0x12, 0x00})
		if err == nil {
			t.Fatal("expected error for wire-type mismatch on known field")
		}
	})

	t.Run("wrong_wire_type_on_nested_height_field", func(t *testing.T) {
		// Outer field 6 is LatestHeight (message). Its nested field 2 is
		// revision_height (varint, wire 0), so wire type 2 must be rejected.
		_, err := DecodeClientState([]byte{0x32, 0x02, 0x12, 0x00})
		if err == nil {
			t.Fatal("expected error for nested wire-type mismatch")
		}
	})

	t.Run("invalid_field_number_zero", func(t *testing.T) {
		_, err := DecodeClientState([]byte{0x00})
		if err == nil {
			t.Fatal("expected error for invalid field number zero")
		}
	})

	t.Run("overflow_length_does_not_panic", func(t *testing.T) {
		// 0x0a = field 1 (ChainID, bytes); the varint length that follows is
		// ~uint64(0). Without the bounds check this overflows int and either
		// panics in make([]byte, length) or sneaks past the underflow guard.
		buf := []byte{0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01}
		_, err := DecodeClientState(buf)
		if err == nil {
			t.Fatal("expected error for overflow length")
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
