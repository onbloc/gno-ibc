package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	pair := realcometbls.OpenZ35CometBLSChannel(cross)
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
	packet := core.Packet{
		SourceChannelId:      pair.Destination,
		DestinationChannelId: core.GetChannel(pair.Destination).CounterpartyChannelId,
		Data:                 e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)),
		TimeoutTimestamp:     core.Timestamp(3600),
	}
	realcometbls.BatchSend(cross, packet)
	marketMaker := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	ack := e2e.MustSuccessAck(cross, mustMarketMakerTokenOrderAck([]byte(marketMaker)))

	core.PacketAcknowledgement(cross, core.MsgPacketAcknowledgement{
		Packets:          []core.Packet{packet},
		Acknowledgements: [][]byte{ack},
		Proof:            realcometbls.Z36AckMembershipProof(cross),
		ProofHeight:      core.Height(realcometbls.DevnetHeight - 1),
	})

	println("commitment_after_ack", core.HasPacketCommitment(cross, packet))
	println("market_maker_balance_after_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))
	println("sender_balance_before_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))

	core.PacketTimeout(cross, core.MsgPacketTimeout{
		Packet:      packet,
		Proof:       realcometbls.Z37ReceiptNonMembershipProof(cross),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
	})

	println("commitment_after_timeout", core.HasPacketCommitment(cross, packet))
	println("market_maker_balance_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))
	println("sender_balance_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))
	println("timeout_after_ack_noop", "ok")
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
// commitment_after_ack false
// market_maker_balance_after_ack 21
// sender_balance_before_timeout 0
// commitment_after_timeout false
// market_maker_balance_after_timeout 21
// sender_balance_after_timeout 0
// timeout_after_ack_noop ok
