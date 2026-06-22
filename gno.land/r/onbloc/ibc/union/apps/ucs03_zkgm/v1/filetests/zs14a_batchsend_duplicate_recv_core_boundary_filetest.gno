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

func main(cur realm) {
	store := zkgm.NewStore()
	app := impl.NewUCS03ZkgmV1(store)

	destination := types.ChannelId(2)
	receiver := string(testutils.TestAddress("zs14a-receiver"))
	quoteToken := impl.PredictWrappedToken(u256.Zero(), uint32(destination), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := types.NewPacket(types.ChannelId(1), destination, mustZS14APacketData(mustZS14ATokenOrderInstruction(order)), types.Timestamp(1<<62))

	println("[SCENARIO] direct impl recv has no core receipt dedupe")
	first := app.OnRecvPacket(0, cur, packet, testutils.TestAddress("zs14a-relayer"), nil)
	second := app.OnRecvPacket(0, cur, packet, testutils.TestAddress("zs14a-relayer"), nil)
	voucher, _ := store.GetVoucher(quoteToken)
	println("first_status", int(first.Status))
	println("second_status", int(second.Status))
	println("quote_balance_after_second_recv", voucher.Token().BalanceOf(address(receiver)))
	println("duplicate_recv_core_boundary", "ok")
}

func mustZS14ATokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func mustZS14APacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] direct impl recv has no core receipt dedupe
// first_status 1
// second_status 1
// quote_balance_after_second_recv 42
// duplicate_recv_core_boundary ok
