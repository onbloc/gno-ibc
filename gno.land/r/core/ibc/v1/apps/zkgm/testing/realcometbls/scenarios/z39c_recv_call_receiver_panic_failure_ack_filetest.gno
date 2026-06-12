// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/unionibc/zkgm"
	"gno.land/r/onbloc/unionibc/v1/core"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"

func main(cur realm) {
	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	packet := callPacket(cur, pair, mockReceiverPath)

	println("[SCENARIO] top-level CALL receiver panic commits a failure ack")
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, realcometbls.Z39CallPacketCommitmentProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))
	println("mock_calls", mock.Calls(cross(cur)))
	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("ack_hash_matches_failure", core.AcknowledgementHash(cross(cur), packet).String() == callFailureAckHash())
}

func callPacket(cur realm, pair realcometbls.ChannelPair, receiverPath string) core.Packet {
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("calldata"),
	}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustCallInstruction(cross(cur), call)), 0, core.Timestamp(0))
}

func callFailureAckHash() string {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("zkgm/v1: receiver panicked: boom")})
	if err != nil {
		panic(err)
	}
	return core.CommitAcks([][]byte{ack}).String()
}

// Output:
// [SCENARIO] top-level CALL receiver panic commits a failure ack
// mock_calls 1
// receipt_after_recv true
// ack_after_recv true
// ack_hash_matches_failure true
