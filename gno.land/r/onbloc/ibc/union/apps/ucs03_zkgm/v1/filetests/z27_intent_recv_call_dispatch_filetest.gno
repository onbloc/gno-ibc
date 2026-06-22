// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const z27MockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	store := zkgm.NewStore()
	store.SetReceiver(0, cur, z27MockReceiverPath, mock.Zkgmable(cross(cur)))
	app := impl.NewUCS03ZkgmV1(store)

	mock.Reset(cross(cur))
	callPacket := types.NewPacket(types.ChannelId(1), types.ChannelId(2),
		mustZ27PacketData(mustZ27CallInstruction(z.Call{
			Sender:           []byte("attacker-sender"),
			ContractAddress:  []byte(z27MockReceiverPath),
			ContractCalldata: []byte("intent-call"),
		})), 0)
	callResult := app.OnIntentRecvPacket(0, cur, callPacket, address("g1maker"), []byte("maker-msg"))
	println("call_status", int(callResult.Status))
	println("call_mock_calls", mock.Calls(cross(cur)))
	println("call_intent_calls", mock.IntentCalls(cross(cur)))
	println("call_last_intent_calldata", mock.LastIntentCalldata(cross(cur)))

	mock.Reset(cross(cur))
	batch := z.Batch{Instructions: []z.Instruction{
		mustZ27CallInstruction(z.Call{
			Sender:           []byte("attacker-sender"),
			ContractAddress:  []byte(z27MockReceiverPath),
			ContractCalldata: []byte("intent-batch-call"),
		}),
	}}
	batchPacket := types.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZ27PacketData(mustZ27BatchInstruction(batch)), 0)
	batchResult := app.OnIntentRecvPacket(0, cur, batchPacket, address("g1maker"), []byte("maker-msg"))
	println("batch_status", int(batchResult.Status))
	println("batch_mock_calls", mock.Calls(cross(cur)))
	println("batch_intent_calls", mock.IntentCalls(cross(cur)))
	println("batch_last_intent_calldata", mock.LastIntentCalldata(cross(cur)))
}

func mustZ27CallInstruction(call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustZ27BatchInstruction(batch z.Batch) z.Instruction {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes}
}

func mustZ27PacketData(instr z.Instruction) []byte {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return packetBytes
}

// Output:
// call_status 1
// call_mock_calls 0
// call_intent_calls 1
// call_last_intent_calldata intent-call
// batch_status 1
// batch_mock_calls 0
// batch_intent_calls 1
// batch_last_intent_calldata intent-batch-call
