package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.Zero(),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.Zero(),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    e2e.MustTokenMetadata(cross, "grc20", "init"),
	}
	packet := core.PacketSend(cross, core.MsgPacketSend{
		SourceChannelId:  pair.Source,
		TimeoutTimestamp: core.Timestamp(3600),
		Data:             e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)),
	})

	println("client", pair.ClientId.String())
	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("packet_sequence", packet.Sequence.String())
	println("packet_source", packet.SourceChannelId.String())
	println("packet_destination", packet.DestinationChannelId.String())
}

// Output:
// client 1
// source_channel 1
// destination_channel 2
// packet_sequence 0
// packet_source 1
// packet_destination 2
