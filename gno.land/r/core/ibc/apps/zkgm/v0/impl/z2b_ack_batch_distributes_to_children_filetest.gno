package main

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	impl "gno.land/r/gnoswap/ibc/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	marketMaker := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	order := z.TokenOrderV2{
		BaseToken:   []byte("ibc/mm-batch"),
		BaseAmount:  u256.NewUint(23),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(),
		mustOrderInstruction(order),
	}}

	err := zkgm.AsIBCApp().OnAcknowledgementPacket(cross, "client-a", "client-b", 1, mustOuterBatchAck([][]byte{
		mustSuccessAck([]byte{}),
		mustSuccessAck(mustTokenOrderAck(marketMaker)),
	}), mustBatchPayload(batch))
	if err != nil {
		panic(err)
	}
	println("mm_balance", impl.VoucherBalanceOf("ibc/mm-batch", address(marketMaker)))
}

func mustCallInstruction() z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{Sender: []byte("sender")})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}
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

func mustTokenOrderAck(marketMaker string) []byte {
	fillType := new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:])
	ack, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: fillType, MarketMaker: []byte(marketMaker)})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// mm_balance 23
