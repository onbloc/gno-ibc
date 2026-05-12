package main

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

const missingReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/missing"

func main() {
	pair := realcometbls.OpenZ35CometBLSChannel(cross)
	packet := callPacket(pair, missingReceiverPath)

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		Proof:       core.NewBytes(cross, realcometbls.Z39MissingCallPacketCommitmentProof(cross)),
		ProofHeight: core.Height(realcometbls.DevnetHeight - 1),
		Relayer:     realcometbls.Relayer,
	})

	println("receipt_after_recv", core.HasPacketReceipt(cross, packet))
	println("ack_after_recv", core.HasAcknowledgement(cross, packet))
	println("recv_call_unregistered_real_cometbls", "ok")
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
// receipt_after_recv true
// ack_after_recv true
// recv_call_unregistered_real_cometbls ok
