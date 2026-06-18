// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	impl.Register(cross(cur))
	mock.Reset(cross(cur))
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	packet := mixedBatchPacket(cur, pair, receiver)

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{[]byte("batch-relay-msg")}, realcometbls.Z40MixedBatchPacketCommitmentProof(cross(cur)), uint64(realcometbls.DevnetHeight-1)))

	println("mock_calls", mock.Calls(cross(cur)))
	println("last_calldata", mock.LastCalldata(cross(cur)))
	println("last_relayer_msg", mock.LastRelayerMsg(cross(cur)))
	println("quote_balance", impl.VoucherBalanceOf("ibc/batch-quote", address(receiver)))
	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("ack_hash_matches_batch_ack", core.AcknowledgementHash(cross(cur), packet).String() == expectedAckHash(cur))
	println("recv_batch_mixed_real_cometbls", "ok")
}

func mixedBatchPacket(cur realm, pair realcometbls.ChannelPair, receiver string) types.Packet {
	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("batch-call"),
		}),
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), types.Timestamp(0))
}

func expectedAckHash(cur realm) string {
	ack := e2e.MustBatchAck(cross(cur), [][]byte{
		e2e.MustCallAck(cross(cur)),
		universalErrorAck(),
	})
	return types.CommitAcks([][]byte{ack}).String()
}

func universalErrorAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("UNIVERSAL_ERROR")})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// mock_calls 1
// last_calldata batch-call
// last_relayer_msg batch-relay-msg
// quote_balance 0
// receipt_after_recv true
// ack_after_recv true
// ack_hash_matches_batch_ack true
// recv_batch_mixed_real_cometbls ok
