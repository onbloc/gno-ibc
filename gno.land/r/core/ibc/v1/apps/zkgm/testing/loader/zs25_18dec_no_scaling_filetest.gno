// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	sh "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	const amount = uint64(1000000000000000000)
	inst := sh.InstallImpl(cross(cur))
	destChannel := core.ChannelId(51)
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	meta := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Ether Token", Symbol: "ETH", Decimals: 18})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(destChannel), []byte("wei"), impl.MetadataImage(sh.DecodeTokenMetadata(meta)))

	println("[SCENARIO] recv 18-dec initialize without amount scaling")
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("wei"),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(50), destChannel, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), 0, core.Timestamp(100))
	inst.Recv(cross(cur), packet, testutils.TestAddress("zs25-relayer"), nil)
	println("voucher_decimals", impl.VoucherDecimalsOf(quoteToken))
	println("receiver_balance", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] unescrow send burns the same 18-dec amount")
	unescrowOrder := z.TokenOrderV2{
		Sender:      []byte(receiver),
		Receiver:    []byte("sender"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte("wei"),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	if _, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), destChannel, core.Timestamp(101), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), unescrowOrder), receiver, "")); err != nil {
		panic(err)
	}
	println("receiver_balance_after_burn", impl.VoucherBalanceOf(quoteToken, address(receiver)))
}

// Output:
// [SCENARIO] recv 18-dec initialize without amount scaling
// voucher_decimals 18
// receiver_balance 1000000000000000000
//
// [SCENARIO] unescrow send burns the same 18-dec amount
// receiver_balance_after_burn 0
