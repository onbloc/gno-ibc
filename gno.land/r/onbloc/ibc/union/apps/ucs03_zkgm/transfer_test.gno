package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

func TestSend_RequiresInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "implementation not installed", func(cur realm) {
		Send(cross(cur), types.ChannelId(7), types.Timestamp(99), [32]byte{}, z.Instruction{})
	})
}

func TestSend_DelegatesToInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	d := &dummyImpl{}
	currentImpl = d
	salt := [32]byte{0xA}
	instruction := z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_CALL,
		Operand: []byte("payload"),
	}

	packet := Send(cross(cur), types.ChannelId(7), types.Timestamp(99), salt, instruction)

	uassert.True(t, d.sendCalled)
	if d.lastChannelId != types.ChannelId(7) {
		t.Fatalf("lastChannelId = %d, want 7", d.lastChannelId)
	}
	if d.lastTimeout != types.Timestamp(99) {
		t.Fatalf("lastTimeout = %d, want 99", d.lastTimeout)
	}
	if d.lastSalt != salt {
		t.Fatal("Send must pass salt through to impl")
	}
	uassert.Equal(t, uint8(z.OP_CALL), d.lastInstruction.Opcode)
	uassert.Equal(t, string(instruction.Operand), string(packet.Data))
	if packet.SourceChannelId != types.ChannelId(7) {
		t.Fatalf("packet.SourceChannelId = %d, want 7", packet.SourceChannelId)
	}
}

func TestSend_RejectsPaused(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	currentImpl = &dummyImpl{}
	paused = true

	uassert.AbortsContains(t, cur, "paused", func(cur realm) {
		Send(cross(cur), types.ChannelId(7), types.Timestamp(99), [32]byte{}, z.Instruction{})
	})
}

func TestSendRaw(cur realm, t *testing.T) {
	cases := []struct {
		name          string
		saltHex       string
		operandHex    string
		wantSaltFirst byte
		wantOperand   string
		wantAbort     string
	}{
		{
			name:          "plain hex",
			saltHex:       "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
			operandHex:    "7061796c6f6164",
			wantSaltFirst: 0x01,
			wantOperand:   "payload",
		},
		{
			name:          "prefixed uppercase hex",
			saltHex:       "0X2102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
			operandHex:    "0x00ff",
			wantSaltFirst: 0x21,
			wantOperand:   string([]byte{0x00, 0xff}),
		},
		{
			name:       "invalid salt hex",
			saltHex:    "zz",
			operandHex: "00",
			wantAbort:  "invalid byte",
		},
		{
			name:       "short salt",
			saltHex:    "0102",
			operandHex: "00",
			wantAbort:  ErrInvalidSaltLength,
		},
		{
			name:       "invalid operand hex",
			saltHex:    "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
			operandHex: "0x0z",
			wantAbort:  "invalid byte",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetZkgmForTest(cur)
			d := &dummyImpl{}
			currentImpl = d

			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					SendRaw(cross(cur), 7, 99, tc.saltHex, z.INSTR_VERSION_0, z.OP_CALL, tc.operandHex)
				})
				uassert.False(t, d.sendCalled)
				return
			}

			uassert.NotAborts(t, cur, func(cur realm) {
				SendRaw(cross(cur), 7, 99, tc.saltHex, z.INSTR_VERSION_0, z.OP_CALL, tc.operandHex)
			})
			uassert.True(t, d.sendCalled)
			uassert.Equal(t, uint32(7), uint32(d.lastChannelId))
			uassert.Equal(t, uint64(99), uint64(d.lastTimeout))
			uassert.Equal(t, tc.wantSaltFirst, d.lastSalt[0])
			uassert.Equal(t, uint8(z.INSTR_VERSION_0), d.lastInstruction.Version)
			uassert.Equal(t, uint8(z.OP_CALL), d.lastInstruction.Opcode)
			uassert.Equal(t, tc.wantOperand, string(d.lastInstruction.Operand))
		})
	}
}

func TestParseHex(t *testing.T) {
	cases := []struct {
		name      string
		input     string
		want      string
		wantError string
	}{
		{"empty", "", "", ""},
		{"plain", "00ff", string([]byte{0x00, 0xff}), ""},
		{"lower prefix", "0x0a", string([]byte{0x0a}), ""},
		{"upper prefix", "0X0b", string([]byte{0x0b}), ""},
		{"odd length", "abc", "", "odd length"},
		{"invalid byte", "zz", "", "invalid byte"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseHex(tc.input)
			if tc.wantError != "" {
				uassert.ErrorContains(t, err, tc.wantError)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, string(got))
		})
	}
}
