package zkgm

import (
	"encoding/hex"
	"testing"
)

func TestInstructionVersions(t *testing.T) {
	if INSTR_VERSION_0 != 0x00 || INSTR_VERSION_1 != 0x01 || INSTR_VERSION_2 != 0x02 {
		t.Fatalf("instruction versions: got %d/%d/%d", INSTR_VERSION_0, INSTR_VERSION_1, INSTR_VERSION_2)
	}
}

func TestOpcodes(t *testing.T) {
	if OP_FORWARD != 0x00 || OP_CALL != 0x01 || OP_BATCH != 0x02 || OP_TOKEN_ORDER != 0x03 {
		t.Fatalf("opcodes: got %d/%d/%d/%d", OP_FORWARD, OP_CALL, OP_BATCH, OP_TOKEN_ORDER)
	}
}

func TestAckConstants(t *testing.T) {
	assertHex(t, "ACK_ERR_ONLY_MAKER", ACK_ERR_ONLY_MAKER, "deadc0de")
	assertHex(t, "TAG_ACK_FAILURE", TAG_ACK_FAILURE[:], "0000000000000000000000000000000000000000000000000000000000000000")
	assertHex(t, "TAG_ACK_SUCCESS", TAG_ACK_SUCCESS[:], "0000000000000000000000000000000000000000000000000000000000000001")
}

func TestFillTypeConstants(t *testing.T) {
	assertHex(t, "FILL_TYPE_PROTOCOL", FILL_TYPE_PROTOCOL[:], "0000000000000000000000000000000000000000000000000000000000b0cad0")
	assertHex(t, "FILL_TYPE_MARKETMAKER", FILL_TYPE_MARKETMAKER[:], "00000000000000000000000000000000000000000000000000000000d1cec45e")
}

func TestTokenOrderKinds(t *testing.T) {
	if TOKEN_ORDER_KIND_INITIALIZE != 0x00 ||
		TOKEN_ORDER_KIND_ESCROW != 0x01 ||
		TOKEN_ORDER_KIND_UNESCROW != 0x02 ||
		TOKEN_ORDER_KIND_SOLVE != 0x03 {
		t.Fatalf("token order kinds: got %d/%d/%d/%d",
			TOKEN_ORDER_KIND_INITIALIZE,
			TOKEN_ORDER_KIND_ESCROW,
			TOKEN_ORDER_KIND_UNESCROW,
			TOKEN_ORDER_KIND_SOLVE,
		)
	}
}

func TestForwardSaltMagic(t *testing.T) {
	assertHex(t, "FORWARD_SALT_MAGIC", FORWARD_SALT_MAGIC[:], "c0de00000000000000000000000000000000000000000000000000000000babe")
}

func TestProtocolVersion(t *testing.T) {
	if PROTOCOL_VERSION != "ucs03-zkgm-0" {
		t.Fatalf("PROTOCOL_VERSION: got %q want %q", PROTOCOL_VERSION, "ucs03-zkgm-0")
	}
}

func assertHex(t *testing.T, name string, got []byte, want string) {
	t.Helper()

	if hex.EncodeToString(got) != want {
		t.Fatalf("%s: got %s want %s", name, hex.EncodeToString(got), want)
	}
}
