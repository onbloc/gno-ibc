// Recv-side happy path: open a channel pair, then submit a TokenOrderV2
// {Kind=ESCROW} packet via core.PacketRecv. dispatchExecute → executeTokenOrderV2
// mints the quote-token voucher on the destination side; we read the resulting
// balance via impl.VoucherBalanceOf to confirm the handler/dispatch path ran
// end-to-end (not just verifyXxx).
package main

import (
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
	quoteDenom := impl.PredictWrappedTokenV1(u256.Zero(), uint32(pair.Destination), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
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
	println("voucher_denom", quoteDenom)
	println("voucher_balance", impl.VoucherBalanceOf(quoteDenom, address(receiver)))
}
