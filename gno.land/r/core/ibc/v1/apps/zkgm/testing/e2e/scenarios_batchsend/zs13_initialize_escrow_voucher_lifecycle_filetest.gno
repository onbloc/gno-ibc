// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	metaBytes := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(pair.Destination), []byte("ugnot"), impl.MetadataImage(mustDecodeTokenMetadata(metaBytes)))

	initialize := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(33),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(33),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	initPacket := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), initialize)), 0, core.Timestamp(1<<62))
	println("[SCENARIO] 1. initialize voucher")
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{initPacket}, nil, nil, core.Height(1)))
	_, hasOriginAfterInitialize := zkgm.GetTokenOrigin(quoteToken)
	println("voucher_balance_after_initialize", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("origin_after_initialize", hasOriginAfterInitialize)
	println("initialize_receipt", core.HasPacketReceipt(cross(cur), initPacket))

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
	escrowPacket := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), escrow)), 0, core.Timestamp(1<<62))
	println("[SCENARIO] 2. escrow into existing voucher")
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{escrowPacket}, nil, nil, core.Height(1)))
	_, hasOriginAfterEscrow := zkgm.GetTokenOrigin(quoteToken)
	println("voucher_balance_after_escrow", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("origin_after_escrow", hasOriginAfterEscrow)
	println("escrow_receipt", core.HasPacketReceipt(cross(cur), escrowPacket))
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// [SCENARIO] 1. initialize voucher
// voucher_balance_after_initialize 33
// origin_after_initialize true
// initialize_receipt true
//
// [SCENARIO] 2. escrow into existing voucher
// voucher_balance_after_escrow 54
// origin_after_escrow true
// escrow_receipt true
