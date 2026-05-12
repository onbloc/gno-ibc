package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"

func main() {
	mock.Reset(cross)
	pair := realcometbls.OpenZ35CometBLSChannel(cross)
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	packet := mixedBatchPacket(pair, receiver)

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		RelayerMsgs: [][]byte{[]byte("batch-relay-msg")},
		Proof:       realcometbls.Z40MixedBatchPacketCommitmentProof(cross),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
	})

	println("mock_calls", mock.Calls(cross))
	println("last_calldata", mock.LastCalldata(cross))
	println("last_relayer_msg", mock.LastRelayerMsg(cross))
	println("quote_balance", impl.VoucherBalanceOf("ibc/batch-quote", address(receiver)))
	println("receipt_after_recv", core.HasPacketReceipt(cross, packet))
	println("ack_after_recv", core.HasAcknowledgement(cross, packet))
	println("ack_hash_matches_batch_ack", core.AcknowledgementHash(cross, packet).String() == expectedAckHash())
	println("recv_batch_mixed_real_cometbls", "ok")
}

func mixedBatchPacket(pair realcometbls.ChannelPair, receiver string) core.Packet {
	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross, z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("batch-call"),
		}),
		e2e.MustTokenOrderInstruction(cross, z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}}
	return core.Packet{
		SourceChannelId:      pair.Source,
		DestinationChannelId: pair.Destination,
		Data:                 e2e.MustPacketData(cross, e2e.MustBatchInstruction(cross, batch)),
		TimeoutTimestamp:     core.Timestamp(0),
	}
}

func expectedAckHash() string {
	ack := e2e.MustBatchAck(cross, [][]byte{
		e2e.MustCallAck(cross),
		e2e.MustSuccessAckBytes(cross, e2e.MustProtocolTokenOrderAck(cross)),
	})
	return core.CommitAcks([][]byte{ack}).String()
}

// Output:
// mock_calls 1
// last_calldata batch-call
// last_relayer_msg batch-relay-msg
// quote_balance 21
// receipt_after_recv true
// ack_after_recv true
// ack_hash_matches_batch_ack true
// recv_batch_mixed_real_cometbls ok
