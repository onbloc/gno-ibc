package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"

func main() {
	mock.Reset(cross)
	pair := realcometbls.OpenZ35CometBLSChannel(cross)
	packet := callPacket(pair, mockReceiverPath)

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		RelayerMsgs: [][]byte{[]byte("relay-msg")},
		Proof:       realcometbls.Z39CallPacketCommitmentProof(cross),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
	})

	println("mock_calls", mock.Calls(cross))
	println("last_sender", mock.LastSender(cross))
	println("last_calldata", mock.LastCalldata(cross))
	println("last_relayer_msg", mock.LastRelayerMsg(cross))
	println("receipt_after_recv", core.HasPacketReceipt(cross, packet))
	println("ack_after_recv", core.HasAcknowledgement(cross, packet))
	println("recv_call_dispatch_real_cometbls", "ok")
}

func callPacket(pair realcometbls.ChannelPair, receiverPath string) core.Packet {
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("calldata"),
	}
	return core.Packet{
		SourceChannelId:      pair.Source,
		DestinationChannelId: pair.Destination,
		Data:                 e2e.MustPacketData(cross, e2e.MustCallInstruction(cross, call)),
		TimeoutTimestamp:     core.Timestamp(0),
	}
}

// Output:
// mock_calls 1
// last_sender sender
// last_calldata calldata
// last_relayer_msg relay-msg
// receipt_after_recv true
// ack_after_recv true
// recv_call_dispatch_real_cometbls ok
