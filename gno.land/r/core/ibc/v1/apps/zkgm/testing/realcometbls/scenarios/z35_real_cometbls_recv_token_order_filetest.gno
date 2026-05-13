package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	pair := realcometbls.OpenZ35CometBLSChannel(cross)

	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("ibc/quote"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.Packet{SourceChannelId: pair.Source, DestinationChannelId: pair.Destination, Data: e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)), TimeoutTimestamp: core.Timestamp(0)}

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		Proof:       realcometbls.Z35PacketCommitmentProof(cross),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
	})

	println("quote_balance", impl.VoucherBalanceOf("ibc/quote", address(receiver)))
	println("ack_hash_matches_failure", core.AcknowledgementHash(cross, packet).String() == expectedFailureAckHash())
}

func expectedFailureAckHash() string {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("UNIVERSAL_ERROR")})
	if err != nil {
		panic(err)
	}
	return core.CommitAcks([][]byte{ack}).String()
}

// Output:
// quote_balance 0
// ack_hash_matches_failure true
