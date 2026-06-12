// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	"chain"
	"chain/banker"
	stdtesting "testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/nonimpl"
	sh "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	inst := sh.InstallImpl(cross(cur))
	sourceChannel := core.ChannelId(10)
	destChannel := core.ChannelId(11)
	sender := "g17xpfvakm2amg962yls6f84z3kell8c5lserqta"
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	relayer := testutils.TestAddress("zs64-relayer")
	meta := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Halted Origin GNOT", Symbol: "HOGNOT", Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(destChannel), []byte("ugnot"), impl.MetadataImage(sh.DecodeTokenMetadata(meta)))

	println("[SCENARIO] lock native on source")
	lockOrder := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	lockInstr := e2e.MustTokenOrderInstruction(cross(cur), lockOrder)
	lockData, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), sourceChannel, core.Timestamp(100), [32]byte{}, lockInstr, sender, "40ugnot"))
	if err != nil {
		panic(err)
	}
	// inst.Send consumes sentCoinBudget bookkeeping only; this mirrors the
	// banker escrow deposit that a real user tx would have locked in the proxy.
	stdtesting.IssueCoins(zkgm.ProxyAddress(), chain.NewCoins(chain.NewCoin("ugnot", 40)))
	println("source_channel_balance_after_lock", sh.ChannelBalanceStr(sourceChannel, u256.Zero(), lockOrder.BaseToken, lockOrder.QuoteToken))
	println("proxy_native_after_lock", banker.NewReadonlyBanker().GetCoins(zkgm.ProxyAddress()).AmountOf("ugnot"))

	println("")
	println("[SCENARIO] mint voucher on destination")
	lockPacket := core.NewPacket(cross(cur), sourceChannel, destChannel, lockData, 0, core.Timestamp(100))
	recvRes := inst.Recv(cross(cur), lockPacket, relayer, nil)
	println("recv_status", int(recvRes.Status))
	println("receiver_voucher_after_mint", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] burn voucher for unescrow send")
	unescrowOrder := z.TokenOrderV2{
		Sender:      []byte(receiver),
		Receiver:    []byte(sender),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	unescrowInstr := e2e.MustTokenOrderInstruction(cross(cur), unescrowOrder)
	_, err = inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), destChannel, core.Timestamp(101), [32]byte{}, unescrowInstr, receiver, ""))
	if err != nil {
		panic(err)
	}
	println("receiver_voucher_after_unescrow_send", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] origin halted: unescrow recv never delivered")
	// A halted origin cannot process the unescrow packet, and timeout refund
	// also requires a fresh non-membership proof from that halted origin.
	bk := banker.NewReadonlyBanker()
	println("source_channel_balance_after_halt", sh.ChannelBalanceStr(sourceChannel, u256.Zero(), lockOrder.BaseToken, lockOrder.QuoteToken))
	println("proxy_native_after_halt", bk.GetCoins(zkgm.ProxyAddress()).AmountOf("ugnot"))
	println("sender_native_after_halt", bk.GetCoins(address(sender)).AmountOf("ugnot"))
	println("receiver_voucher_final", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("release_native_unauthorized_caller_rejected", releaseNativeUnauthorizedCallerRejected(cur))
}

func releaseNativeUnauthorizedCallerRejected(cur realm) bool {
	var tt *stdtesting.T
	return uassert.AbortsContains(tt, cur, "not an authorized impl", func(cur realm) {
		nonimpl.ReleaseNativeDirect(cross(cur))
	})
}

// Output:
// [SCENARIO] lock native on source
// source_channel_balance_after_lock 40
// proxy_native_after_lock 40
//
// [SCENARIO] mint voucher on destination
// recv_status 1
// receiver_voucher_after_mint 40
//
// [SCENARIO] burn voucher for unescrow send
// receiver_voucher_after_unescrow_send 0
//
// [SCENARIO] origin halted: unescrow recv never delivered
// source_channel_balance_after_halt 40
// proxy_native_after_halt 40
// sender_native_after_halt 0
// receiver_voucher_final 0
// release_native_unauthorized_caller_rejected true
