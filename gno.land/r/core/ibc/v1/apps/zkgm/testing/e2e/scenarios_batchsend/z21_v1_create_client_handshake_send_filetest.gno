// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	z "gno.land/p/onbloc/unionibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/onbloc/unionibc/v1/core"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.Zero(),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.Zero(),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    e2e.MustTokenMetadata(cross(cur), "grc20", "init"),
	}
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), 0, core.Timestamp(3600))
	e2e.BatchSend(cross(cur), packet)

	println("client", pair.ClientId.String())
	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("packet_source", packet.SourceChannelId.String())
	println("packet_destination", packet.DestinationChannelId.String())
}

// Output:
// client 1
// source_channel 1
// destination_channel 2
// packet_source 1
// packet_destination 2
