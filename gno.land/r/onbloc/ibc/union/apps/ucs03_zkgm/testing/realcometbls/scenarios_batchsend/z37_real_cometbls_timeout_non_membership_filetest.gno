// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
	pair := realcometbls.OpenZ37CometBLSChannel(cross(cur))
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
	packet := core.NewPacket(cross(cur), pair.Destination, core.GetChannel(pair.Destination).CounterpartyChannelId, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(3600))
	realcometbls.BatchSend(cross(cur), packet)

	println("commitment_before_timeout", core.HasPacketCommitment(cross(cur), packet))
	println("sender_balance_before_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))

	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(packet, realcometbls.Z37ReceiptNonMembershipProof(cross(cur)), uint64(realcometbls.DevnetHeight-1)))

	println("commitment_after_timeout", core.HasPacketCommitment(cross(cur), packet))
	println("sender_balance_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))
	println("timeout_real_cometbls", "ok")
}

// Output:
// commitment_before_timeout true
// sender_balance_before_timeout 0
// commitment_after_timeout false
// sender_balance_after_timeout 21
// timeout_real_cometbls ok
