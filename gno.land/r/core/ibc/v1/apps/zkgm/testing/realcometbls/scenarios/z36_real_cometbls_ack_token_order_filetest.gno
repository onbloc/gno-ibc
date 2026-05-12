package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	pair := realcometbls.OpenZ35CometBLSChannel(cross)

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
		BaseToken:   []byte("ibc/base"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.PacketSend(cross, core.MsgPacketSend{
		SourceChannelId:  pair.Destination,
		TimeoutTimestamp: core.Timestamp(3600),
		Data:             e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)),
	})
	marketMaker := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	ack := e2e.MustSuccessAck(cross, mustMarketMakerTokenOrderAck([]byte(marketMaker)))

	println("packet_sequence", packet.Sequence.String())
	println("commitment_before_ack", core.HasPacketCommitment(cross, packet))
	println("market_maker_balance_before_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))

	core.PacketAcknowledgement(cross, core.MsgPacketAcknowledgement{
		Packets:          []core.Packet{packet},
		Acknowledgements: []core.Bytes{ack},
		Proof:            core.NewBytes(cross, realcometbls.Z36AckMembershipProof(cross)),
		ProofHeight:      core.Height(realcometbls.DevnetHeight - 1),
		Relayer:          realcometbls.Relayer,
	})

	println("commitment_after_ack", core.HasPacketCommitment(cross, packet))
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
// packet_sequence 0
// commitment_before_ack true
// market_maker_balance_before_ack 0
// commitment_after_ack false
// market_maker_balance_after_ack 21
// ack_real_cometbls ok
