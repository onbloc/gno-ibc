package main

import (
	"crypto/keccak256"
	"encoding/hex"

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
	mock.SetPanic(cross, "boom")
	pair := realcometbls.OpenZ35CometBLSChannel(cross)
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	packet := panicBatchPacket(pair, receiver)

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		Proof:       realcometbls.Z40PanicBatchPacketCommitmentProof(cross),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
	})

	println("mock_calls", mock.Calls(cross))
	println("quote_balance", impl.VoucherBalanceOf("ibc/batch-panic-quote", address(receiver)))
	println("receipt_after_recv", core.HasPacketReceipt(cross, packet))
	println("ack_after_recv", core.HasAcknowledgement(cross, packet))
	println("ack_hash_matches_only_maker", core.AcknowledgementHash(cross, packet).String() == onlyMakerAckHash())
	println("recv_batch_child_panic_real_cometbls", "ok")
}

func panicBatchPacket(pair realcometbls.ChannelPair, receiver string) core.Packet {
	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross, z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		e2e.MustTokenOrderInstruction(cross, z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-panic-quote"),
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

func onlyMakerAckHash() string {
	ack := make([]byte, len(z.ACK_ERR_ONLY_MAKER))
	copy(ack, z.ACK_ERR_ONLY_MAKER)
	hash := keccak256.Sum256(ack)
	return "0x" + hex.EncodeToString(hash[:])
}

// Output:
// mock_calls 1
// quote_balance 0
// receipt_after_recv true
// ack_after_recv true
// ack_hash_matches_only_maker true
// recv_batch_child_panic_real_cometbls ok
