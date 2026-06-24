package core

import (
	"bytes"
	"encoding/hex"
	"strings"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// Mirrors gno-core/gnovm/stdlibs/chain/emit_event.go MaxEventAttrLen.
const emitMaxEventAttrLen = 1024

// 2 hex chars per byte plus the "0x" prefix
const boundaryRawLen = (emitMaxEventAttrLen - 2) / 2

type binaryFixture struct {
	name string
	data []byte
}

func binaryFixtures() []binaryFixture {
	return []binaryFixture{
		{"empty", []byte{}},
		{"single_zero", []byte{0x00}},
		{"all_0xFF_32B", bytes.Repeat([]byte{0xFF}, 32)},
		{"abi_padding_32B", append(bytes.Repeat([]byte{0x00}, 31), 0x2A)},
		{"continuation_only_0x80", []byte{0x80}},
		{"lone_surrogate_pair", []byte{0xED, 0xA0, 0x80}},
		{"high_entropy_480B", pseudoRandomBytes(0xC0FFEE, 480)},
	}
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

func mustEncodeRealZkgmPacket(t *testing.T) []byte {
	t.Helper()
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"),
		ContractCalldata: pseudoRandomBytes(0xBADC0DE, 480),
	})
	if err != nil {
		t.Fatalf("encode call: %v", err)
	}
	out, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_CALL,
			Operand: callBytes,
		},
	})
	if err != nil {
		t.Fatalf("encode packet: %v", err)
	}
	return out
}

func decodeBinaryAttr(t *testing.T, encoded string) []byte {
	t.Helper()
	if !strings.HasPrefix(encoded, "0x") {
		t.Fatalf("missing 0x prefix: %q", encoded)
	}
	out, err := hex.DecodeString(strings.TrimPrefix(encoded, "0x"))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	return out
}

func assertRoundTrip(t *testing.T, data []byte) {
	t.Helper()
	encoded := hexAttr(data)
	if len(encoded) > emitMaxEventAttrLen {
		t.Fatalf("fixture too large for round-trip test: encoded len %d", len(encoded))
	}
	decoded := decodeBinaryAttr(t, encoded)
	if !bytes.Equal(data, decoded) {
		t.Errorf("round-trip mismatch:\n  in : %x\n  out: %x", data, decoded)
	}
}

func TestEmitBinaryFieldsRoundTrip(cur realm, t *testing.T) {
	for _, fx := range binaryFixtures() {
		t.Run(fx.name, func(t *testing.T) {
			assertRoundTrip(t, fx.data)
		})
	}
}

func TestEmitBinaryFieldsBoundary(cur realm, t *testing.T) {
	t.Run("exact_1024", func(t *testing.T) {
		raw := make([]byte, boundaryRawLen)
		for i := range raw {
			raw[i] = byte(i)
		}
		if got := len(hexAttr(raw)); got != emitMaxEventAttrLen {
			t.Fatalf("encoded len = %d, want %d", got, emitMaxEventAttrLen)
		}
		assertRoundTrip(t, raw)
	})

	t.Run("one_byte_over_limit", func(t *testing.T) {
		raw := make([]byte, boundaryRawLen+1)
		if got := len(hexAttr(raw)); got <= emitMaxEventAttrLen {
			t.Fatalf("encoded len = %d, want > %d", got, emitMaxEventAttrLen)
		}
	})

	t.Run("realistic_zkgm_packet_exceeds_limit", func(t *testing.T) {
		got := len(hexAttr(mustEncodeRealZkgmPacket(t)))
		if got <= emitMaxEventAttrLen {
			t.Fatalf("realistic ZKGM packet len = %d, want > %d", got, emitMaxEventAttrLen)
		}
	})
}

func TestEmittersAllowProxyRealmCaller(cur realm, t *testing.T) {
	EmitPacketRecv(0, cur, types.Packet{}, types.Channel{}, types.Connection{}, nil)
}
