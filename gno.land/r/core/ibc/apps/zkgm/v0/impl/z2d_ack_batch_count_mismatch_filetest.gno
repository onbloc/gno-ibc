package main

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	batch := z.Batch{Instructions: []z.Instruction{mustCallInstruction("a"), mustCallInstruction("b")}}
	err := zkgm.AsIBCApp().OnAcknowledgementPacket(cross, "client-a", "client-b", 1, mustOuterBatchAck([][]byte{mustSuccessAck([]byte{})}), mustBatchPayload(batch))
	println("error_message", err.Error())
}

func mustCallInstruction(calldata string) z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{Sender: []byte("sender"), ContractCalldata: []byte(calldata)})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustBatchPayload(batch z.Batch) types.Payload {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes}})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
}

func mustOuterBatchAck(childAcks [][]byte) []byte {
	batchAck, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: childAcks})
	if err != nil {
		panic(err)
	}
	return mustSuccessAck(batchAck)
}

func mustSuccessAck(inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(1), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// error_message zkgm/v0: batch ack count mismatch
