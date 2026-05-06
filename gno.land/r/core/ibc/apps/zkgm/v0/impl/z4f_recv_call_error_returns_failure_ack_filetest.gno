package main

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	"gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"

func main() {
	mock.Reset(cross)
	mock.SetError(cross, "receiver failed")

	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-b", 1, mustCallPayload(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	}))
	ack, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}

	println("status", int(res.Status))
	println("ack_tag", ack.Tag.Dec())
	println("inner_ack", string(ack.InnerAck))
	println("mock_calls", mock.Calls())
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
// inner_ack receiver failed
// mock_calls 1
