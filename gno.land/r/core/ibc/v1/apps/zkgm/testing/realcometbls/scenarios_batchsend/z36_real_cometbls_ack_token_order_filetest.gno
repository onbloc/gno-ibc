// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios_batchsend
package scenarios_batchsend

import (
	z "gno.land/p/onbloc/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	core "gno.land/r/onbloc/unionibc/v1/core"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
	realcometbls "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
)

func main(cur realm) {
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	sender := string(testutils.TestAddress("timeout-sender"))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
		BaseToken:   []byte("ibc/base"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(cross(cur), pair.Destination, core.GetChannel(pair.Destination).CounterpartyChannelId, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), 0, core.Timestamp(3600))
	realcometbls.BatchSend(cross(cur), packet)
	marketMaker := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	ack := e2e.MustSuccessAck(cross(cur), mustMarketMakerTokenOrderAck([]byte(marketMaker)))

	println("commitment_before_ack", core.HasPacketCommitment(cross(cur), packet))
	println("market_maker_balance_before_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))

	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement(cross(cur), []core.Packet{packet}, [][]byte{ack}, realcometbls.Z36AckMembershipProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))

	println("commitment_after_ack", core.HasPacketCommitment(cross(cur), packet))
	println("market_maker_balance_after_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))
	println("ack_real_cometbls", "ok")
}

func mustMarketMakerTokenOrderAck(marketMaker []byte) []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:]),
		MarketMaker: marketMaker,
	})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// commitment_before_ack true
// market_maker_balance_before_ack 0
// commitment_after_ack false
// market_maker_balance_after_ack 21
// ack_real_cometbls ok
