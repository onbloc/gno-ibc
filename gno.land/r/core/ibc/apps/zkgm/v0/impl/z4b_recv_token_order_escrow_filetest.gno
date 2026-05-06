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
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("ibc/quote"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-b", 1, mustOrderPayload(order))
	ack, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}

	println("status", int(res.Status))
	println("ack_tag", ack.Tag.Dec())
	println("quote_balance", impl.VoucherBalanceOf("ibc/quote", address(receiver)))
}

func mustOrderPayload(order z.TokenOrderV2) types.Payload {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path: u256.NewUint(2),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_2,
			Opcode:  z.OP_TOKEN_ORDER,
			Operand: orderBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
}

// Output:
// status 1
// ack_tag 1
// quote_balance 21
