package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	sender := "g17xpfvakm2amg962yls6f84z3kell8c5lserqta"
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.Zero(),
		QuoteToken:  []byte("ibc/quote"),
		QuoteAmount: u256.NewUint(33),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    e2e.MustTokenMetadata(cross, "grc20", "roundtrip"),
	}
	instr := e2e.MustTokenOrderInstruction(cross, order)
	packet := core.PacketSend(cross, core.MsgPacketSend{
		SourceChannelId:  pair.Source,
		TimeoutTimestamp: core.Timestamp(3600),
		Data:             e2e.MustPacketData(cross, instr),
	})

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		Proof:       core.NewBytes(cross, nil),
		ProofHeight: core.Height(1),
		Relayer:     e2e.Relayer,
	})

	ack := e2e.MustSuccessAck(cross, e2e.MustProtocolTokenOrderAck(cross))
	core.PacketAcknowledgement(cross, core.MsgPacketAcknowledgement{
		Packets:          []core.Packet{packet},
		Acknowledgements: []core.Bytes{ack},
		Proof:            core.NewBytes(cross, nil),
		ProofHeight:      core.Height(1),
		Relayer:          e2e.Relayer,
	})

	println("packet_sequence", packet.Sequence.String())
	println("quote_balance", impl.VoucherBalanceOf(impl.PredictWrappedTokenV2(pair.Destination, order.BaseToken, impl.MetadataImage(mustDecodeTokenMetadata(order.Metadata))), address(receiver)))
	println("ack_roundtrip", "ok")
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// packet_sequence 0
// quote_balance 33
// ack_roundtrip ok
