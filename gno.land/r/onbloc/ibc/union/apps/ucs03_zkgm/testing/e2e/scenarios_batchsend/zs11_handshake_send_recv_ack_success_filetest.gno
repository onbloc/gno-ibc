// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
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
	packet := core.NewPacket(pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(1<<62))

	// BatchSend commits the packet directly, so this file covers the core
	// lifecycle flags and recv-side mint. Send-side escrow is covered elsewhere.
	println("[SCENARIO] 1. open channel and commit packet")
	e2e.BatchSend(cross(cur), packet)
	println("source_channel", packet.SourceChannelId.String())
	println("destination_channel", packet.DestinationChannelId.String())
	println("commitment_after_send", core.HasPacketCommitment(cross(cur), packet))
	println("receipt_before_recv", core.HasPacketReceipt(cross(cur), packet))

	println("")
	println("[SCENARIO] 2. recv success")
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, nil, 1))
	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("quote_balance_after_recv", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] 3. ack success")
	ack := e2e.MustSuccessAck(cross(cur), e2e.MustProtocolTokenOrderAck(cross(cur)))
	core.PacketAcknowledgement(cross(cur), types.NewMsgPacketAcknowledgement([]types.Packet{packet}, [][]byte{ack}, nil, 1))
	println("commitment_after_ack", core.HasPacketCommitment(cross(cur), packet))
	println("receipt_after_ack", core.HasPacketReceipt(cross(cur), packet))
	println("ack_success_roundtrip", "ok")
}

// Output:
// [SCENARIO] 1. open channel and commit packet
// source_channel 1
// destination_channel 2
// commitment_after_send true
// receipt_before_recv false
//
// [SCENARIO] 2. recv success
// receipt_after_recv true
// ack_after_recv true
// quote_balance_after_recv 21
//
// [SCENARIO] 3. ack success
// commitment_after_ack false
// receipt_after_ack true
// ack_success_roundtrip ok
