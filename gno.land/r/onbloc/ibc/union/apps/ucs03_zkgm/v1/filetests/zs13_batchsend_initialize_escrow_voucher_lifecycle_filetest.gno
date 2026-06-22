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
	receiver := string(testutils.TestAddress("zs13-receiver"))
	meta := mustZS13TokenMetadata("Gno Token", "GNOT", 6)
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(destination), []byte("ugnot"), impl.MetadataImage(mustZS13DecodeTokenMetadata(meta)))

	initialize := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(33),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(33),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	initPacket := types.NewPacket(types.ChannelId(1), destination, mustZS13PacketData(mustZS13TokenOrderInstruction(initialize)), types.Timestamp(1<<62))
	println("[SCENARIO] 1. initialize voucher")
	app.OnRecvPacket(0, cur, initPacket, testutils.TestAddress("zs13-relayer"), nil)
	voucher, _ := store.GetVoucher(quoteToken)
	_, originAfterInitialize := store.GetTokenOrigin(quoteToken)
	println("voucher_balance_after_initialize", voucher.Token().BalanceOf(address(receiver)))
	println("origin_after_initialize", originAfterInitialize)

	println("")
	escrow := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	escrowPacket := types.NewPacket(types.ChannelId(1), destination, mustZS13PacketData(mustZS13TokenOrderInstruction(escrow)), types.Timestamp(1<<62))
	println("[SCENARIO] 2. escrow into existing voucher")
	app.OnRecvPacket(0, cur, escrowPacket, testutils.TestAddress("zs13-relayer"), nil)
	_, originAfterEscrow := store.GetTokenOrigin(quoteToken)
	println("voucher_balance_after_escrow", voucher.Token().BalanceOf(address(receiver)))
	println("origin_after_escrow", originAfterEscrow)
}

func mustZS13TokenMetadata(name string, symbol string, decimals uint8) []byte {
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

func mustZS13DecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func mustZS13TokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func mustZS13PacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] 1. initialize voucher
// voucher_balance_after_initialize 33
// origin_after_initialize true
//
// [SCENARIO] 2. escrow into existing voucher
// voucher_balance_after_escrow 54
// origin_after_escrow true
