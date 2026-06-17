// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
	core "gno.land/r/onbloc/ibc/union/core"
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
		Metadata:    e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6}),
	}
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(3600))
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
