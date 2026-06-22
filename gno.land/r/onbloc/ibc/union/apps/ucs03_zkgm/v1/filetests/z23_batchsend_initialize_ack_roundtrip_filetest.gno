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
	receiver := string(testutils.TestAddress("z23-receiver"))
	meta := mustZ23TokenMetadata("Gno Token", "GNOT", 6)
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(destination), []byte("ugnot"), impl.MetadataImage(mustZ23DecodeTokenMetadata(meta)))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(33),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(33),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := types.NewPacket(source, destination, mustZ23PacketData(mustZ23TokenOrderInstruction(order)), types.Timestamp(1<<62))

	recv := app.OnRecvPacket(0, cur, packet, testutils.TestAddress("z23-relayer"), nil)
	app.OnAcknowledgementPacket(0, cur, packet, mustZ23SuccessAck(mustZ23ProtocolTokenOrderAck()), testutils.TestAddress("z23-relayer"))
	voucher, _ := store.GetVoucher(quoteToken)

	println("recv_status", int(recv.Status))
	println("quote_balance", voucher.Token().BalanceOf(address(receiver)))
	println("ack_roundtrip", "ok")
}

func mustZ23TokenMetadata(name string, symbol string, decimals uint8) []byte {
	init, err := z.EncodeTokenInitializer(z.TokenInitializer{Name: name, Symbol: symbol, Decimals: decimals})
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: []byte("grc20"), Initializer: init})
	if err != nil {
		panic(err)
	}
	return meta
}

func mustZ23DecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func mustZ23TokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func mustZ23PacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZ23ProtocolTokenOrderAck() []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZ23SuccessAck(inner []byte) []byte {
	bz, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// recv_status 1
// quote_balance 33
// ack_roundtrip ok
