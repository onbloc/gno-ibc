// Ack-side probe for TokenOrderV2 market-maker fill handling. It commits a sent
// ESCROW packet whose base token is an IBC voucher, delivers a successful
// market-maker acknowledgement, and confirms the voucher is paid to the market
// maker rather than released as a native banker coin.
package main

import (
	"chain/runtime"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	sender := runtime.OriginCaller().String()
	marketMaker := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	baseToken := []byte("ugnot-mm-ack")
	voucherDenom := impl.PredictWrappedToken(
		u256.Zero(),
		uint32(pair.Destination),
		baseToken,
	)

	recvOrder := z.TokenOrderV2{
		Sender:      []byte("counterparty"),
		Receiver:    []byte(sender),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(voucherDenom),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	recvPacket := core.Packet{
		SourceChannelId:      pair.Source,
		DestinationChannelId: pair.Destination,
		Data:                 e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, recvOrder)),
	}
	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{recvPacket},
		ProofHeight: core.Height(1),
	})

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("counterparty-receiver"),
		BaseToken:   []byte(voucherDenom),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  baseToken,
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := zkgm.Send(
		cross,
		pair.Destination,
		core.Timestamp(3600),
		[32]byte{},
		e2e.MustTokenOrderInstruction(cross, order),
	)

	ack := e2e.MustSuccessAck(cross, mustMarketMakerTokenOrderAck([]byte(marketMaker)))
	println("commitment_before_ack", core.HasPacketCommitment(cross, packet))
	println(
		"sender_balance_before_ack",
		impl.VoucherBalanceOf(string(order.BaseToken), address(sender)),
	)
	println(
		"market_maker_balance_before_ack",
		impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)),
	)

	core.PacketAcknowledgement(cross, core.MsgPacketAcknowledgement{
		Packets:          []core.Packet{packet},
		Acknowledgements: [][]byte{ack},
		ProofHeight:      core.Height(1),
	})

	println("commitment_after_ack", core.HasPacketCommitment(cross, packet))
	println(
		"sender_balance_after_ack",
		impl.VoucherBalanceOf(string(order.BaseToken), address(sender)),
	)
	println(
		"market_maker_balance_after_ack",
		impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)),
	)
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
