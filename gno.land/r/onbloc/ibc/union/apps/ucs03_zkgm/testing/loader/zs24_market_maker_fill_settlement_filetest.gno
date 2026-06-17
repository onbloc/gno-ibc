// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader
package loader

import (
	types "gno.land/p/onbloc/ibc/union/types"

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
	inst := sh.InstallImpl(cross(cur))
	sender := string(testutils.TestAddress("zs24-sender"))
	receiver := string(testutils.TestAddress("zs24-receiver"))
	marketMaker := testutils.TestAddress("zs24-market-maker")
	baseToken := sh.MintVoucher(cross(cur), inst, types.ChannelId(40), "base/zs24", sender, 30, "ZS24")
	quoteToken := sh.MintVoucher(cross(cur), inst, types.ChannelId(41), "quote/zs24", marketMaker.String(), 12, "ZS24")
	channelId := types.ChannelId(42)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(30),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	println("[SCENARIO] market maker fills quote side")
	intentPacket := core.NewPacket(cross(cur), types.ChannelId(99), types.ChannelId(98), e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(100))
	intentRes := inst.IntentRecv(cross(cur), intentPacket, marketMaker, nil)
	println("intent_status", int(intentRes.Status))
	println("market_maker_quote_after_fill", impl.VoucherBalanceOf(quoteToken, marketMaker))
	println("receiver_quote_after_fill", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] proven ack settles recorded maker")
	sendData, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), channelId, types.Timestamp(101), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), order), sender, ""))
	if err != nil {
		panic(err)
	}
	sourcePacket := core.NewPacket(cross(cur), channelId, types.ChannelId(100), sendData, types.Timestamp(101))
	println("sender_base_after_send", impl.VoucherBalanceOf(baseToken, address(sender)))
	println("channel_after_send", sh.ChannelBalanceStr(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	inst.Ack(cross(cur), sourcePacket, intentRes.Acknowledgement, testutils.TestAddress("zs24-relayer"))
	println("ack_market_maker_recorded", zs24AckMarketMaker(intentRes.Acknowledgement) == marketMaker.String())
	println("market_maker_base_after_ack", impl.VoucherBalanceOf(baseToken, marketMaker))
	println("channel_after_ack", sh.ChannelBalanceStr(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
}

func zs24AckMarketMaker(ackBytes []byte) string {
	ack, err := z.DecodeAck(ackBytes)
	if err != nil {
		panic(err)
	}
	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	if err != nil {
		panic(err)
	}
	return string(orderAck.MarketMaker)
}

// Output:
// [SCENARIO] market maker fills quote side
// intent_status 1
// market_maker_quote_after_fill 0
// receiver_quote_after_fill 12
//
// [SCENARIO] proven ack settles recorded maker
// sender_base_after_send 0
// channel_after_send 30
// ack_market_maker_recorded true
// market_maker_base_after_ack 30
// channel_after_ack 0
