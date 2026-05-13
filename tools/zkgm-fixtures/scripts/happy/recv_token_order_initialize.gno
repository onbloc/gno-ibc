// Recv-side probe for TokenOrderV2{INITIALIZE}. It verifies that the
// predicted quote token is minted to the receiver and that BaseAmount -
// QuoteAmount is minted to the relayer as the protocol fee.
package main

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	relayer := runtime.OriginCaller().String()
	metaBytes := e2e.MustTokenMetadata(cross, "grc20", "initialize-smoke")
	meta := mustDecodeTokenMetadata(metaBytes)
	quoteDenom := impl.PredictWrappedTokenV2(
		u256.Zero(),
		uint32(pair.Destination),
		[]byte("ugnot-init"),
		impl.MetadataImage(meta),
	)
	order := z.TokenOrderV2{
		Sender:      []byte("counterparty"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot-init"),
		BaseAmount:  u256.NewUint(33),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.Packet{
		SourceChannelId:      pair.Source,
		DestinationChannelId: pair.Destination,
		Data:                 e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)),
	}

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		ProofHeight: core.Height(1),
	})

	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("quote_denom", quoteDenom)
	println("receiver_balance", impl.VoucherBalanceOf(quoteDenom, address(receiver)))
	println("relayer_fee_balance", impl.VoucherBalanceOf(quoteDenom, address(relayer)))
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}
