// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	u256 "gno.land/p/gnoswap/uint256"

	z "gno.land/p/onbloc/unionibc/zkgm"
	"gno.land/r/onbloc/unionibc/v1/core"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"

	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"

func main(cur realm) {
	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	packet := panicBatchPacket(cur, pair, receiver)

	println("[SCENARIO] CALL-first batch receiver panic commits child failure ack")
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, realcometbls.Z40PanicBatchPacketCommitmentProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))
	println("mock_calls", mock.Calls(cross(cur)))
	println("quote_balance", impl.VoucherBalanceOf("ibc/batch-panic-quote", address(receiver)))
	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("ack_hash_matches_batch_ack", core.AcknowledgementHash(cross(cur), packet).String() == panicBatchExpectedAckHash(cur))
}

func panicBatchPacket(cur realm, pair realcometbls.ChannelPair, receiver string) core.Packet {
	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-panic-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), 0, core.Timestamp(0))
}

func panicBatchExpectedAckHash(cur realm) string {
	ack := e2e.MustBatchAck(cross(cur), [][]byte{
		callFailureAck(),
		panicBatchUniversalErrorAck(),
	})
	return core.CommitAcks([][]byte{ack}).String()
}

func callFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("zkgm/v1: receiver panicked: boom")})
	if err != nil {
		panic(err)
	}
	return ack
}

func panicBatchUniversalErrorAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("UNIVERSAL_ERROR")})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] CALL-first batch receiver panic commits child failure ack
// mock_calls 1
// quote_balance 0
// receipt_after_recv true
// ack_after_recv true
// ack_hash_matches_batch_ack true
