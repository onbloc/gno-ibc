// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct
package scenarios_direct

import (
	"chain"
	"chain/banker"

	types "gno.land/p/onbloc/ibc/union/types"

	stdtesting "testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	sh "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	inst := sh.InstallV1Harness(cross(cur))
	sourceChannel := types.ChannelId(10)
	destChannel := types.ChannelId(11)
	sender := "g17xpfvakm2amg962yls6f84z3kell8c5lserqta"
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	relayer := testutils.TestAddress("zs21-relayer")
	meta := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Roundtrip GNOT", Symbol: "RGNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(destChannel), []byte("ugnot"), z.MetadataImage(sh.DecodeTokenMetadata(meta)))

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
	lockData, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), sourceChannel, types.Timestamp(100), [32]byte{}, lockInstr, sender, "40ugnot"))
	if err != nil {
		panic(err)
	}
	println("source_channel_balance_after_lock", sh.ChannelBalanceStr(sourceChannel, u256.Zero(), lockOrder.BaseToken, lockOrder.QuoteToken))

	println("")
	println("[SCENARIO] mint voucher on destination")
	lockPacket := core.NewPacket(sourceChannel, destChannel, lockData, types.Timestamp(100))
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
	unescrowData, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), destChannel, types.Timestamp(101), [32]byte{}, unescrowInstr, receiver, ""))
	if err != nil {
		panic(err)
	}
	println("receiver_voucher_after_unescrow_send", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] unlock native on source")
	// inst.Send consumes sentCoinBudget bookkeeping only; this simulates the
	// banker escrow deposit that a real user tx would have locked in the proxy.
	stdtesting.IssueCoins(zkgm.ProxyAddress(), chain.NewCoins(chain.NewCoin("ugnot", 40)))
	unescrowPacket := core.NewPacket(destChannel, sourceChannel, unescrowData, types.Timestamp(101))
	unescrowRes := inst.Recv(cross(cur), unescrowPacket, relayer, nil)
	bk := banker.NewReadonlyBanker()
	println("unescrow_recv_status", int(unescrowRes.Status))
	println("source_channel_balance_after_unlock", sh.ChannelBalanceStr(sourceChannel, u256.Zero(), lockOrder.BaseToken, lockOrder.QuoteToken))
	println("sender_native_after_unlock", bk.GetCoins(address(sender)).AmountOf("ugnot"))
	println("receiver_voucher_final", impl.VoucherBalanceOf(quoteToken, address(receiver)))
}

// Output:
// [SCENARIO] lock native on source
// source_channel_balance_after_lock 40
//
// [SCENARIO] mint voucher on destination
// recv_status 1
// receiver_voucher_after_mint 40
//
// [SCENARIO] burn voucher for unescrow send
// receiver_voucher_after_unescrow_send 0
//
// [SCENARIO] unlock native on source
// unescrow_recv_status 1
// source_channel_balance_after_unlock 0
// sender_native_after_unlock 40
// receiver_voucher_final 0
