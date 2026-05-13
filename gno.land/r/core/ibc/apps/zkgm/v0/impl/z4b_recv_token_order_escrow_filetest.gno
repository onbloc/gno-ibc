package main

import (
	"chain/runtime"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	impl "gno.land/r/gnoswap/ibc/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	receiver := string(testutils.TestAddress("receiver"))
	quoteToken := impl.PredictWrappedTokenV1(u256.NewUint(2), 1, []byte("ugnot"))
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-1", 1, mustOrderPayload(order))
	ack, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}

	println("status", int(res.Status))
	println("ack_tag", ack.Tag.Dec())
	println("quote_balance", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("relayer_balance", impl.VoucherBalanceOf(quoteToken, runtime.OriginCaller()))
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
// relayer_balance 79
