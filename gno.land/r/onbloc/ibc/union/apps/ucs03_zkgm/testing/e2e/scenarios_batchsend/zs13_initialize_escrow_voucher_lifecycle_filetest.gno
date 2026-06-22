// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
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
	initPacket := core.NewPacket(pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), initialize)), types.Timestamp(1<<62))
	println("[SCENARIO] 1. initialize voucher")
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{initPacket}, nil, nil, 1))
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
	escrowPacket := core.NewPacket(pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), escrow)), types.Timestamp(1<<62))
	println("[SCENARIO] 2. escrow into existing voucher")
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{escrowPacket}, nil, nil, 1))
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
