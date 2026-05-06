package main

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-b", 1, mustCallPayload(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte("gno.land/r/notregistered/foo"),
	}))
	ack, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}

	println("status", int(res.Status))
	println("ack_tag", ack.Tag.Dec())
	println("inner_ack", string(ack.InnerAck))
}

func mustCallPayload(call z.Call) types.Payload {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
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
	return types.Payload{Value: packetBytes}
}

// Output:
// status 2
// ack_tag 0
// inner_ack zkgm/v0: receiver not registered: gno.land/r/notregistered/foo
