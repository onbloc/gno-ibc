// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	z "gno.land/p/onbloc/unionibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/onbloc/unionibc/v1/core"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	parentChannel := e2e.OpenE2EChannel(cross(cur), core.ChannelId(101))
	childSource := e2e.OpenE2EChannel(cross(cur), core.ChannelId(102))

	forward := z.Forward{
		Path:             e2e.ForwardPath(cross(cur), uint32(parentChannel), uint32(childSource)),
		TimeoutTimestamp: 999,
		Instruction: e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte("gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"),
			ContractCalldata: []byte("forward-core-frame"),
		}),
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), parentChannel,
		e2e.MustPacketData(cross(cur), e2e.MustForwardInstruction(cross(cur), forward)), 0, core.Timestamp(0))

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))

	expectedChild := e2e.MustForwardChildPacket(cross(cur), packet, u256.Zero(), [32]byte{}, forward)
	_, inFlight := zkgm.GetInFlightPacket(zkgm.NewInFlightKey(cross(cur), core.CommitPacket(expectedChild)))

	println("impl_path", zkgm.ImplPath())
	println("child_source", expectedChild.SourceChannelId.String())
	println("child_destination", expectedChild.DestinationChannelId.String())
	println("in_flight", inFlight)
	println("parent_ack", core.HasAcknowledgement(cross(cur), packet))
	println("forward_allowedimpls_positive", "ok")
}

// Output:
// impl_path gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
// child_source 2
// child_destination 102
// in_flight true
// parent_ack false
// forward_allowedimpls_positive ok
