// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const missingReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/missing"

func main(cur realm) {
	impl.Register(cross(cur))
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	packet := callPacket(cur, pair, missingReceiverPath)

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, realcometbls.Z39MissingCallPacketCommitmentProof(cross(cur)), uint64(realcometbls.DevnetHeight-1)))

	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("recv_call_unregistered_real_cometbls", "ok")
}

func callPacket(cur realm, pair realcometbls.ChannelPair, receiverPath string) types.Packet {
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("calldata"),
	}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustCallInstruction(cross(cur), call)), types.Timestamp(0))
}

// Output:
// receipt_after_recv true
// ack_after_recv true
// recv_call_unregistered_real_cometbls ok
