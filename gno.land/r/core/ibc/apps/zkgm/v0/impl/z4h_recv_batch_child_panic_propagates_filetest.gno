package main

import (
	"encoding/hex"

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
	mock.SetPanic(cross, "boom")

	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-b", 1, mustBatchPayload(z.Batch{
		Instructions: []z.Instruction{
			mustCallInstruction("first"),
			mustCallInstruction("second"),
		},
	}))

	println("status", int(res.Status))
	println("ack_hex", hex.EncodeToString(res.Acknowledgement))
	println("mock_calls", mock.Calls())
	println("last_calldata", mock.LastCalldata(cross))
}

func mustBatchPayload(batch z.Batch) types.Payload {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_BATCH,
			Operand: batchBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
}

func mustCallInstruction(calldata string) z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte(calldata),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

// Output:
// status 1
// ack_hex deadc0de
// mock_calls 1
// last_calldata first
