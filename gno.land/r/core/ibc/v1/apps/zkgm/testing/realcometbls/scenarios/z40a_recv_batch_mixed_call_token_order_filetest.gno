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
	mock.Reset(cross(cur))
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	packet := mixedBatchPacket(pair, receiver)

	core.PacketRecv(cross(cur), core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		RelayerMsgs: [][]byte{[]byte("batch-relay-msg")},
		Proof:       realcometbls.Z40MixedBatchPacketCommitmentProof(cross(cur)),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
	})

	println("mock_calls", mock.Calls(cross(cur)))
	println("last_calldata", mock.LastCalldata(cross(cur)))
	println("last_relayer_msg", mock.LastRelayerMsg(cross(cur)))
	println("quote_balance", impl.VoucherBalanceOf("ibc/batch-quote", address(receiver)))
	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("ack_hash_matches_batch_ack", core.AcknowledgementHash(cross(cur), packet).String() == expectedAckHash())
	println("recv_batch_mixed_real_cometbls", "ok")
}

func mixedBatchPacket(pair realcometbls.ChannelPair, receiver string) core.Packet {
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
	return core.Packet{
		SourceChannelId:      pair.Source,
		DestinationChannelId: pair.Destination,
		Data:                 e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)),
		TimeoutTimestamp:     core.Timestamp(0),
	}
}

func expectedAckHash() string {
	ack := e2e.MustBatchAck(cross(cur), [][]byte{
		e2e.MustCallAck(cross(cur)),
		universalErrorAck(),
	})
	return core.CommitAcks([][]byte{ack}).String()
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
