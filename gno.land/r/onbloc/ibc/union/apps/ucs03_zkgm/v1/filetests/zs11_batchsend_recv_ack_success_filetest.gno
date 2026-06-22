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

	source := types.ChannelId(1)
	destination := types.ChannelId(2)
	receiver := string(testutils.TestAddress("zs11-receiver"))
	relayer := testutils.TestAddress("zs11-relayer")
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
	packet := types.NewPacket(source, destination, mustZS11PacketData(mustZS11TokenOrderInstruction(order)), types.Timestamp(1<<62))

	println("[SCENARIO] recv success")
	recv := app.OnRecvPacket(0, cur, packet, relayer, nil)
	voucher, _ := store.GetVoucher(quoteToken)
	println("recv_status", int(recv.Status))
	println("quote_balance_after_recv", voucher.Token().BalanceOf(address(receiver)))

	println("")
	println("[SCENARIO] ack success")
	app.OnAcknowledgementPacket(0, cur, packet, mustZS11SuccessAck(mustZS11ProtocolTokenOrderAck()), relayer)
	println("ack_success_roundtrip", "ok")
}

func mustZS11TokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func mustZS11PacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZS11ProtocolTokenOrderAck() []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZS11SuccessAck(inner []byte) []byte {
	bz, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] recv success
// recv_status 1
// quote_balance_after_recv 21
//
// [SCENARIO] ack success
// ack_success_roundtrip ok
