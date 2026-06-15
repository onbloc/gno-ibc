// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	z "gno.land/p/onbloc/ibc/zkgm"
	core "gno.land/r/onbloc/ibc/core"
	e2e "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e"
	"gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/mock"
	realcometbls "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls"
	_ "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1/loader"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	mock.Reset(cross(cur))
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	packet := callPacket(cur, pair, mockReceiverPath)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, [][]byte{[]byte("relay-msg")}, realcometbls.Z39CallPacketCommitmentProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))

	println("mock_calls", mock.Calls(cross(cur)))
	println("last_sender", mock.LastSender(cross(cur)))
	println("last_calldata", mock.LastCalldata(cross(cur)))
	println("last_relayer_msg", mock.LastRelayerMsg(cross(cur)))
	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("recv_call_dispatch_real_cometbls", "ok")
}

func callPacket(cur realm, pair realcometbls.ChannelPair, receiverPath string) core.Packet {
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("calldata"),
	}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustCallInstruction(cross(cur), call)), 0, core.Timestamp(0))
}

// Output:
// mock_calls 1
// last_sender sender
// last_calldata calldata
// last_relayer_msg relay-msg
// receipt_after_recv true
// ack_after_recv true
// recv_call_dispatch_real_cometbls ok
