// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	"gno.land/p/nt/testutils/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

// RecvPacket dispatches an ESCROW token order, distributing vouchers to the
// receiver and the relayer. The filetest drives the v1 impl directly with a real
// zkgm Store, matching the unit tests' injection model without needing the
// admin-gated proxy/core install flow.
func main(cur realm) {
	store := zkgm.NewStore()
	app := impl.NewUCS03ZkgmV1(store)

	source := types.ChannelId(1)
	destination := types.ChannelId(2)
	receiver := string(testutils.TestAddress("receiver"))
	relayer := testutils.TestAddress("relayer")
	quoteToken := impl.PredictWrappedToken(u256.Zero(), uint32(destination), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := types.NewPacket(source, destination, mustPacketData(mustTokenOrderInstruction(order)), 0)

	result := app.OnRecvPacket(0, cur, packet, relayer, nil)
	voucher, _ := store.GetVoucher(quoteToken)

	println("status", int(result.Status))
	println("quote_balance", voucher.Token().BalanceOf(address(receiver)))
	println("relayer_balance", voucher.Token().BalanceOf(relayer))
}

func mustTokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: orderBytes,
	}
}

func mustPacketData(instr z.Instruction) []byte {
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
// status 1
// quote_balance 21
// relayer_balance 79
