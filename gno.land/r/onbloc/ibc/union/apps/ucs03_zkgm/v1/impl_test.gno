package impl

import (
	"testing"

	z "gno.land/p/onbloc/ibc/zkgm"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func TestSendAppliesSenderSalt(cur realm, t *testing.T) {
	sender := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	salt := [32]byte{0x44}
	callBytes, err := z.EncodeCall(z.Call{
		Sender:          []byte(sender),
		ContractAddress: []byte(mockReceiverPath),
	})
	uassert.NoError(t, err)

	data, err := (&ZkgmV1{}).Send(cur, zkgm.NewSendRequest(
		cross(cur),
		core.ChannelId(1),
		0,
		salt,
		z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_CALL,
			Operand: callBytes,
		},
		sender,
		"",
	))
	uassert.NoError(t, err)

	packet, err := z.DecodeZkgmPacket(data)
	uassert.NoError(t, err)
	if packet.Salt != z.DeriveSenderSalt([]byte(sender), salt) {
		t.Fatal("Send did not apply DeriveSenderSalt")
	}
	if packet.Salt == salt {
		t.Fatal("Send wrote raw salt")
	}
}
