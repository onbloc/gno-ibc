package impl

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func TestSendAppliesSenderSalt(cur realm, t *testing.T) {
	sender := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	salt := [32]byte{0x44}
	callBytes, err := z.EncodeCall(z.Call{
		Sender:          []byte(sender),
		ContractAddress: []byte(mockReceiverPath),
	})
	uassert.NoError(t, err)

	data, err := (&ZkgmV1{}).Send(cur, zkgm.SendRequest{
		ChannelId: core.ChannelId(1),
		Salt:      salt,
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_CALL,
			Operand: callBytes,
		},
		Sender: sender,
	})
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
