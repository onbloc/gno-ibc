package core

import (
	"bytes"
	"encoding/hex"
	"strings"
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
)

// Kept in sync with gno-core/gnovm/stdlibs/chain/emit_event.go.
const (
	emitMaxEventAttrLen = 1024
	emitTruncMarker     = "..."
)

type binaryFixture struct {
	name string
	data []byte
}

func binaryFixtures() []binaryFixture {
	return []binaryFixture{
		{"empty", []byte{}},
		{"single_zero", []byte{0x00}},
		{"all_0xFF_32B", repeatByte(0xFF, 32)},
		{"abi_padding_32B", append(repeatByte(0x00, 31), 0x2A)},
		{"continuation_only_0x80", []byte{0x80}},
		{"lone_surrogate_pair", []byte{0xED, 0xA0, 0x80}},
		{"high_entropy_480B", pseudoRandomBytes(0xC0FFEE, 480)},
	}
}

func repeatByte(b byte, n int) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = b
	}
	return out
}

func pseudoRandomBytes(seed uint64, n int) []byte {
	out := make([]byte, n)
	x := seed
	for i := range out {
		x = x*6364136223846793005 + 1442695040888963407
		out[i] = byte(x >> 32)
	}
	return out
}

func mustEncodeRealZkgmPacket() []byte {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte("gno.land/r/core/ibc/v1/apps/zkgm/testing/mock"),
		ContractCalldata: pseudoRandomBytes(0xBADC0DE, 480),
	})
	if err != nil {
		panic(err)
	}

	out, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: [32]byte{
			0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
			0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
			0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
			0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
		},
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_CALL,
			Operand: callBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return out
}

func decodeBinaryAttr(t *testing.T, field string, encoded string) []byte {
	t.Helper()
	if !strings.HasPrefix(encoded, "0x") {
		t.Fatalf("%s: missing 0x prefix: %q", field, encoded)
	}
	out, err := hex.DecodeString(strings.TrimPrefix(encoded, "0x"))
	if err != nil {
		t.Fatalf("%s: decode: %v", field, err)
	}
	return out
}

func assertRoundTrip(t *testing.T, field string, data []byte) {
	t.Helper()
	encoded := hexAttr(data)
	if len(encoded) > emitMaxEventAttrLen {
		t.Fatalf("%s: fixture too large for round-trip test: encoded len %d", field, len(encoded))
	}
	decoded := decodeBinaryAttr(t, field, encoded)
	if !bytes.Equal(data, decoded) {
		t.Errorf("%s: round-trip mismatch:\n  in : %x\n  out: %x", field, data, decoded)
	}
}

func simulateEmitTruncation(s string) string {
	if len(s) <= emitMaxEventAttrLen {
		return s
	}
	return s[:emitMaxEventAttrLen] + emitTruncMarker
}

func TestEmitBinaryFieldsRoundTrip(t *testing.T) {
	for _, fx := range binaryFixtures() {
		t.Run(fx.name, func(t *testing.T) {
			assertRoundTrip(t, "packet_data", fx.data)
			assertRoundTrip(t, "acknowledgement", fx.data)
			assertRoundTrip(t, "maker_msg", fx.data)
			assertRoundTrip(t, "market_maker_msg", fx.data)
		})
	}
}

func TestEmitBinaryFieldsTruncationBoundary(t *testing.T) {
	raw := make([]byte, 511)
	for i := range raw {
		raw[i] = byte(i)
	}
	encoded := hexAttr(raw)
	if len(encoded) != emitMaxEventAttrLen {
		t.Fatalf("setup: encoded len = %d, want %d", len(encoded), emitMaxEventAttrLen)
	}
	assertRoundTrip(t, "packet_data_boundary", raw)

	oversized := append(raw, 0xFF)
	encoded = hexAttr(oversized)
	if len(encoded) <= emitMaxEventAttrLen {
		t.Fatalf("setup: oversized encoded len = %d, want > %d", len(encoded), emitMaxEventAttrLen)
	}
	truncated := simulateEmitTruncation(encoded)
	if !strings.HasSuffix(truncated, emitTruncMarker) {
		t.Fatalf("oversized payload must carry truncation marker")
	}
	if len(truncated) != emitMaxEventAttrLen+len(emitTruncMarker) {
		t.Fatalf("truncated len = %d, want %d", len(truncated), emitMaxEventAttrLen+len(emitTruncMarker))
	}

	realistic := hexAttr(mustEncodeRealZkgmPacket())
	if len(realistic) <= emitMaxEventAttrLen {
		t.Fatalf("setup: realistic ZKGM packet len = %d, want > %d", len(realistic), emitMaxEventAttrLen)
	}
	if !strings.HasSuffix(simulateEmitTruncation(realistic), emitTruncMarker) {
		t.Fatalf("realistic ZKGM packet must carry truncation marker")
	}
}
