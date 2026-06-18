// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct
package scenarios_direct

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
	inst := sh.InstallV1Harness(cross(cur))
	senderRefund := string(testutils.TestAddress("zs23-refund-sender"))
	senderSuccess := string(testutils.TestAddress("zs23-success-sender"))
	refundBaseToken := sh.MintVoucher(cross(cur), inst, types.ChannelId(30), "base/zs23-refund", senderRefund, 100, "ZS23")
	successBaseToken := sh.MintVoucher(cross(cur), inst, types.ChannelId(31), "base/zs23-success", senderSuccess, 100, "ZS23")
	refundChannel := types.ChannelId(32)
	successChannel := types.ChannelId(33)

	println("[SCENARIO] send-side escrow for both branches")
	refundOrder := zs23Order(senderRefund, refundBaseToken)
	successOrder := zs23Order(senderSuccess, successBaseToken)
	refundPacket := zs23Send(cross(cur), inst, refundChannel, senderRefund, refundOrder)
	successPacket := zs23Send(cross(cur), inst, successChannel, senderSuccess, successOrder)
	println("refund_sender_after_send", impl.VoucherBalanceOf(refundBaseToken, address(senderRefund)))
	println("success_sender_after_send", impl.VoucherBalanceOf(successBaseToken, address(senderSuccess)))
	println("refund_channel_after_send", sh.ChannelBalanceStr(refundChannel, u256.Zero(), refundOrder.BaseToken, refundOrder.QuoteToken))
	println("success_channel_after_send", sh.ChannelBalanceStr(successChannel, u256.Zero(), successOrder.BaseToken, successOrder.QuoteToken))

	println("")
	println("[SCENARIO] failure ack refunds sender")
	inst.Ack(cross(cur), refundPacket, zs23FailureAckBytes(), testutils.TestAddress("zs23-relayer"))
	println("refund_sender_after_failure_ack", impl.VoucherBalanceOf(refundBaseToken, address(senderRefund)))
	println("refund_channel_after_failure_ack", sh.ChannelBalanceStr(refundChannel, u256.Zero(), refundOrder.BaseToken, refundOrder.QuoteToken))

	println("")
	println("[SCENARIO] success protocol ack leaves escrow settled")
	inst.Ack(cross(cur), successPacket, e2e.MustSuccessAck(cross(cur), e2e.MustProtocolTokenOrderAck(cross(cur))), testutils.TestAddress("zs23-relayer"))
	println("success_sender_after_success_ack", impl.VoucherBalanceOf(successBaseToken, address(senderSuccess)))
	println("success_channel_after_success_ack", sh.ChannelBalanceStr(successChannel, u256.Zero(), successOrder.BaseToken, successOrder.QuoteToken))
}

func zs23Order(sender string, baseToken string) z.TokenOrderV2 {
	return z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("quote/zs23"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
}

func zs23Send(cur realm, inst zkgm.ZkgmImpl, channelId types.ChannelId, sender string, order z.TokenOrderV2) types.Packet {
	data, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), channelId, types.Timestamp(120), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), order), sender, ""))
	if err != nil {
		panic(err)
	}
	return core.NewPacket(cross(cur), channelId, types.ChannelId(99), data, types.Timestamp(120))
}

func zs23FailureAckBytes() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:])})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] send-side escrow for both branches
// refund_sender_after_send 79
// success_sender_after_send 79
// refund_channel_after_send 21
// success_channel_after_send 21
//
// [SCENARIO] failure ack refunds sender
// refund_sender_after_failure_ack 100
// refund_channel_after_failure_ack 0
//
// [SCENARIO] success protocol ack leaves escrow settled
// success_sender_after_success_ack 79
// success_channel_after_success_ack 21
