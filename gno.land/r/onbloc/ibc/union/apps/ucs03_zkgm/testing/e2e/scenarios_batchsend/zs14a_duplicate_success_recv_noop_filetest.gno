// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	quoteToken := impl.PredictWrappedTokenV1(u256.Zero(), uint32(pair.Destination), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(1<<62))
	msg := types.NewMsgPacketRecv([]types.Packet{packet}, nil, nil, 1)

	println("quote_balance_before_recv", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("[SCENARIO] 1. first recv mints")
	core.PacketRecv(cross(cur), msg)
	println("receipt_after_first_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_first_recv", core.HasAcknowledgement(cross(cur), packet))
	println("quote_balance_after_first_recv", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] 2. duplicate recv is skipped")
	core.PacketRecv(cross(cur), msg)
	println("receipt_after_second_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_second_recv", core.HasAcknowledgement(cross(cur), packet))
	println("quote_balance_after_second_recv", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("duplicate_success_recv_noop", "ok")
}

// Output:
// quote_balance_before_recv 0
// [SCENARIO] 1. first recv mints
// receipt_after_first_recv true
// ack_after_first_recv true
// quote_balance_after_first_recv 21
//
// [SCENARIO] 2. duplicate recv is skipped
// receipt_after_second_recv true
// ack_after_second_recv true
// quote_balance_after_second_recv 21
// duplicate_success_recv_noop ok
