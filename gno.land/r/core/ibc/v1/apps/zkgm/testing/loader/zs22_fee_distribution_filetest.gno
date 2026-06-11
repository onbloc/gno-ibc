// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	"chain"
	"chain/banker"
	stdtesting "testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	sh "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	inst := sh.InstallImpl(cross(cur))
	relayer := testutils.TestAddress("zs22-relayer")
	receiver := string(testutils.TestAddress("zs22-receiver"))
	escrowChannel := core.ChannelId(21)
	unescrowChannel := core.ChannelId(22)
	meta := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Fee Token", Symbol: "FEE", Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(escrowChannel), []byte("ufee"), impl.MetadataImage(sh.DecodeTokenMetadata(meta)))

	println("[SCENARIO] escrow recv fee mints voucher split")
	escrowOrder := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ufee"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(88),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	escrowPacket := core.NewPacket(cross(cur), core.ChannelId(20), escrowChannel, sh.TokenOrderPacketData(cross(cur), escrowOrder), 0, core.Timestamp(100))
	inst.Recv(cross(cur), escrowPacket, relayer, nil)
	println("receiver_voucher", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("relayer_voucher_fee", impl.VoucherBalanceOf(quoteToken, relayer))

	println("")
	println("[SCENARIO] unescrow recv fee releases native split")
	nativeLock := z.TokenOrderV2{
		Sender:      []byte(testutils.TestAddress("zs22-native-sender").String()),
		Receiver:    []byte(testutils.TestAddress("zs22-counterparty").String()),
		BaseToken:   []byte("ufee"),
		BaseAmount:  u256.NewUint(55),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(55),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	lockData, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), unescrowChannel, core.Timestamp(101), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), nativeLock), string(nativeLock.Sender), "55ufee"))
	if err != nil {
		panic(err)
	}
	_ = lockData
	nativeOrder := z.TokenOrderV2{
		Sender:      []byte(testutils.TestAddress("zs22-counterparty").String()),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(55),
		QuoteToken:  []byte("ufee"),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	// inst.Send consumes sentCoinBudget bookkeeping only; this simulates the
	// banker escrow deposit that a real user tx would have locked in the proxy.
	stdtesting.IssueCoins(zkgm.ProxyAddress(), chain.NewCoins(chain.NewCoin("ufee", 55)))
	unescrowPacket := core.NewPacket(cross(cur), core.ChannelId(23), unescrowChannel, sh.TokenOrderPacketData(cross(cur), nativeOrder), 0, core.Timestamp(102))
	inst.Recv(cross(cur), unescrowPacket, relayer, nil)
	bk := banker.NewReadonlyBanker()
	println("receiver_native", bk.GetCoins(address(receiver)).AmountOf("ufee"))
	println("relayer_native_fee", bk.GetCoins(relayer).AmountOf("ufee"))
	println("unescrow_channel_balance", sh.ChannelBalanceStr(unescrowChannel, u256.Zero(), nativeOrder.QuoteToken, nativeOrder.BaseToken))
}

// Output:
// [SCENARIO] escrow recv fee mints voucher split
// receiver_voucher 88
// relayer_voucher_fee 12
//
// [SCENARIO] unescrow recv fee releases native split
// receiver_native 50
// relayer_native_fee 5
// unescrow_channel_balance 0
