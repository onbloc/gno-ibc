// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	z "gno.land/p/onbloc/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/e2e"
	realcometbls "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/onbloc/ibc/v1/apps/zkgm/v0/loader"
)

const missingReceiverPath = "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/missing"

func main(cur realm) {
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	packet := callPacket(cur, pair, missingReceiverPath)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, realcometbls.Z39MissingCallPacketCommitmentProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))

	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("recv_call_unregistered_real_cometbls", "ok")
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
// receipt_after_recv true
// ack_after_recv true
// recv_call_unregistered_real_cometbls ok
