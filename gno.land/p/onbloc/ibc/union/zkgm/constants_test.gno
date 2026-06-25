package zkgm

import (
	"encoding/hex"
	"testing"
)

func TestInstructionVersions(t *testing.T) {
	tests := []struct {
		name string
		got  byte
		want byte
	}{
		{"v0", INSTR_VERSION_0, 0x00},
		{"v1", INSTR_VERSION_1, 0x01},
		{"v2", INSTR_VERSION_2, 0x02},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Fatalf("got %d want %d", tt.got, tt.want)
			}
		})
	}
}

func TestOpcodes(t *testing.T) {
	tests := []struct {
		name string
		got  byte
		want byte
	}{
		{"forward", OP_FORWARD, 0x00},
		{"call", OP_CALL, 0x01},
		{"batch", OP_BATCH, 0x02},
		{"token order", OP_TOKEN_ORDER, 0x03},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Fatalf("got %d want %d", tt.got, tt.want)
			}
		})
	}
}

func TestAckConstants(t *testing.T) {
	tests := []struct {
		name string
		got  []byte
		want string
	}{
		{"ACK_ERR_ONLY_MAKER", ACK_ERR_ONLY_MAKER, "deadc0de"},
		{"TAG_ACK_FAILURE", TAG_ACK_FAILURE[:], "0000000000000000000000000000000000000000000000000000000000000000"},
		{"TAG_ACK_SUCCESS", TAG_ACK_SUCCESS[:], "0000000000000000000000000000000000000000000000000000000000000001"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertHex(t, tt.name, tt.got, tt.want)
		})
	}
}

func TestFillTypeConstants(t *testing.T) {
	tests := []struct {
		name string
		got  []byte
		want string
	}{
		{"FILL_TYPE_PROTOCOL", FILL_TYPE_PROTOCOL[:], "0000000000000000000000000000000000000000000000000000000000b0cad0"},
		{"FILL_TYPE_MARKETMAKER", FILL_TYPE_MARKETMAKER[:], "00000000000000000000000000000000000000000000000000000000d1cec45e"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertHex(t, tt.name, tt.got, tt.want)
		})
	}
}

func TestTokenOrderKinds(t *testing.T) {
	tests := []struct {
		name string
		got  byte
		want byte
	}{
		{"initialize", TOKEN_ORDER_KIND_INITIALIZE, 0x00},
		{"escrow", TOKEN_ORDER_KIND_ESCROW, 0x01},
		{"unescrow", TOKEN_ORDER_KIND_UNESCROW, 0x02},
		{"solve", TOKEN_ORDER_KIND_SOLVE, 0x03},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Fatalf("got %d want %d", tt.got, tt.want)
			}
		})
	}
}

func TestForwardSaltMagic(t *testing.T) {
	tests := []struct {
		name string
		got  []byte
		want string
	}{
		{"FORWARD_SALT_MAGIC", FORWARD_SALT_MAGIC[:], "c0de00000000000000000000000000000000000000000000000000000000babe"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertHex(t, tt.name, tt.got, tt.want)
		})
	}
}

func TestProtocolVersion(t *testing.T) {
	tests := []struct {
		name string
		got  string
		want string
	}{
		{"PROTOCOL_VERSION", PROTOCOL_VERSION, "ucs03-zkgm-0"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Fatalf("got %q want %q", tt.got, tt.want)
			}
		})
	}
}

func assertHex(t *testing.T, name string, got []byte, want string) {
	t.Helper()

	if hex.EncodeToString(got) != want {
		t.Fatalf("%s: got %s want %s", name, hex.EncodeToString(got), want)
	}
}
