// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const z40RecvMockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	store := zkgm.NewStore()
	store.SetReceiver(0, cur, z40RecvMockReceiverPath, mock.Zkgmable(cross(cur)))
	app := impl.NewUCS03ZkgmV1(store)

	mock.Reset(cross(cur))
	mixedResult := app.OnRecvPacket(0, cur, z40RecvMixedBatchPacket(), address("g1relayer"), []byte("batch-relay-msg"))
	println("mixed_status", int(mixedResult.Status))
	println("mixed_mock_calls", mock.Calls(cross(cur)))
	println("mixed_last_calldata", mock.LastCalldata(cross(cur)))
	println("mixed_last_relayer_msg", mock.LastRelayerMsg(cross(cur)))
	println("mixed_only_maker", string(mixedResult.Acknowledgement) == string(z.ACK_ERR_ONLY_MAKER))

	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	panicResult := app.OnRecvPacket(0, cur, z40RecvPanicBatchPacket(), address("g1relayer"), nil)
	println("panic_status", int(panicResult.Status))
	println("panic_mock_calls", mock.Calls(cross(cur)))
	println("panic_only_maker", string(panicResult.Acknowledgement) == string(z.ACK_ERR_ONLY_MAKER))
}

func z40RecvMixedBatchPacket() types.Packet {
	return z40RecvBatchPacket(z.Batch{Instructions: []z.Instruction{
		mustZ40RecvCallInstruction(z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(z40RecvMockReceiverPath),
			ContractCalldata: []byte("batch-call"),
		}),
		mustZ40RecvTokenOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}})
}

func z40RecvPanicBatchPacket() types.Packet {
	return z40RecvBatchPacket(z.Batch{Instructions: []z.Instruction{
		mustZ40RecvCallInstruction(z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(z40RecvMockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		mustZ40RecvTokenOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-panic-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}})
}

func z40RecvBatchPacket(batch z.Batch) types.Packet {
	return types.NewPacket(types.ChannelId(2), types.ChannelId(1), mustZ40RecvPacketData(mustZ40RecvBatchInstruction(batch)), types.Timestamp(0))
}

func mustZ40RecvCallInstruction(call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustZ40RecvTokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}
}

func mustZ40RecvBatchInstruction(batch z.Batch) z.Instruction {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes}
}

func mustZ40RecvPacketData(instr z.Instruction) []byte {
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
// mixed_status 1
// mixed_mock_calls 1
// mixed_last_calldata batch-call
// mixed_last_relayer_msg batch-relay-msg
// mixed_only_maker true
// panic_status 1
// panic_mock_calls 1
// panic_only_maker true
