// Recv-side probe for OP_BATCH: Batch of two TokenOrderV2{ESCROW}, each
// minting a different voucher denom on the destination chain. Exercises
// dispatchExecute's batch loop, per-sub-instruction ack assembly into a
// BatchAck, and the WriteAck commit with the wrapped Success ack.
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

	receiverA := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	receiverB := "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

	orderA := z.TokenOrderV2{
		Sender:      []byte("counterparty"),
		Receiver:    []byte(receiverA),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("ibc/alpha"),
		QuoteAmount: u256.NewUint(11),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	orderB := z.TokenOrderV2{
		Sender:      []byte("counterparty"),
		Receiver:    []byte(receiverB),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(200),
		QuoteToken:  []byte("ibc/beta"),
		QuoteAmount: u256.NewUint(22),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustTokenOrderInstruction(cross, orderA),
		e2e.MustTokenOrderInstruction(cross, orderB),
	}}
	packet := core.Packet{
		SourceChannelId:      pair.Source,
		DestinationChannelId: pair.Destination,
		Data:                 e2e.MustPacketData(cross, e2e.MustBatchInstruction(cross, batch)),
	}

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		ProofHeight: core.Height(1),
	})

	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("alpha_balance", impl.VoucherBalanceOf("ibc/alpha", address(receiverA)))
	println("beta_balance", impl.VoucherBalanceOf("ibc/beta", address(receiverB)))
}
