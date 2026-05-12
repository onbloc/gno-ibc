package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	pair := realcometbls.OpenZ35CometBLSChannel(cross)
	sender := string(testutils.TestAddress("timeout-sender"))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
		BaseToken:   []byte("ibc/base"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.PacketSend(cross, core.MsgPacketSend{
		SourceChannelId:  pair.Destination,
		TimeoutTimestamp: core.Timestamp(3600),
		Data:             e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)),
	})

	println("commitment_before_timeout", core.HasPacketCommitment(cross, packet))
	println("sender_balance_before_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))

	core.PacketTimeout(cross, core.MsgPacketTimeout{
		Packet:      packet,
		Proof:       core.NewBytes(cross, realcometbls.Z37ReceiptNonMembershipProof(cross)),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
		Relayer:     realcometbls.Relayer,
	})

	println("commitment_after_timeout", core.HasPacketCommitment(cross, packet))
	println("sender_balance_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))
	println("timeout_real_cometbls", "ok")
}

// Output:
// commitment_before_timeout true
// sender_balance_before_timeout 0
// commitment_after_timeout false
// sender_balance_after_timeout 21
// timeout_real_cometbls ok
