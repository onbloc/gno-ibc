// Ack-side probe for TokenOrderV2 refund handling. It commits a sent
// UNESCROW packet, delivers a failure acknowledgement, and confirms the
// voucher is refunded to the original sender.
package main

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	sender := runtime.OriginCaller().String()
	baseToken := []byte("ugnot-ack")
	voucherDenom := impl.PredictWrappedTokenV1(
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
		Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
		BaseToken:   []byte(voucherDenom),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  baseToken,
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := zkgm.Send(
		cross,
		pair.Destination,
		core.Timestamp(3600),
		[32]byte{},
		e2e.MustTokenOrderInstruction(cross, order),
	)

	failureAck := e2e.MustAck(cross, u256.Zero(), []byte("counterparty failed"))
	println("commitment_before_ack", core.HasPacketCommitment(cross, packet))
	println(
		"sender_balance_before_ack",
		impl.VoucherBalanceOf(string(order.BaseToken), address(sender)),
	)

	core.PacketAcknowledgement(cross, core.MsgPacketAcknowledgement{
		Packets:          []core.Packet{packet},
		Acknowledgements: [][]byte{failureAck},
		ProofHeight:      core.Height(1),
	})

	println("commitment_after_ack", core.HasPacketCommitment(cross, packet))
	println(
		"sender_balance_after_ack",
		impl.VoucherBalanceOf(string(order.BaseToken), address(sender)),
	)
}
