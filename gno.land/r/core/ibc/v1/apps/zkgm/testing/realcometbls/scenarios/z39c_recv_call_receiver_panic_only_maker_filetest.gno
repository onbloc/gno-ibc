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
	mock.SetPanic(cross, "boom")
	pair := realcometbls.OpenZ35CometBLSChannel(cross)
	packet := callPacket(pair, mockReceiverPath)

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		Proof:       core.NewBytes(cross, realcometbls.Z39CallPacketCommitmentProof(cross)),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
		Relayer:     realcometbls.Relayer,
	})

	println("mock_calls", mock.Calls(cross))
	println("receipt_after_recv", core.HasPacketReceipt(cross, packet))
	println("ack_after_recv", core.HasAcknowledgement(cross, packet))
	println("recv_call_panic_contained_real_cometbls", "ok")
}

func callPacket(pair realcometbls.ChannelPair, receiverPath string) core.Packet {
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("calldata"),
	}
	return core.NewPacket(
		cross,
		core.Sequence(9),
		pair.Source,
		pair.Destination,
		e2e.MustPacketData(cross, e2e.MustCallInstruction(cross, call)),
		core.Timestamp(0),
	)
}

// Output:
// mock_calls 1
// receipt_after_recv true
// ack_after_recv true
// recv_call_panic_contained_real_cometbls ok
