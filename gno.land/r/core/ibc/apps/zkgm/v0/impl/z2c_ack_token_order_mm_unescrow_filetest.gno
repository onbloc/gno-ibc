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
		BaseToken:   []byte("ibc/mm"),
		BaseAmount:  u256.NewUint(23),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	err := zkgm.AsIBCApp().OnAcknowledgementPacket(cross, "client-a", "client-b", 1, mustSuccessAck(mustTokenOrderAck(marketMaker)), mustOrderPayload(order))
	if err != nil {
		panic(err)
	}
	println("mm_balance", impl.VoucherBalanceOf("ibc/mm", address(marketMaker)))
}

func mustOrderPayload(order z.TokenOrderV2) types.Payload {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
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
