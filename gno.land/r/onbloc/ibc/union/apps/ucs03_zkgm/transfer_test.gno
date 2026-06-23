package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

func TestSendRequiresInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest()

	uassert.AbortsContains(t, cur, "implementation not installed", func(cur realm) {
		Send(cross(cur), types.ChannelId(7), types.Timestamp(99), [32]byte{}, z.Instruction{})
	})
}

func TestSendDelegatesToInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest()

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
