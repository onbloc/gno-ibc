// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	parentChannel := e2e.OpenE2EChannel(cross(cur), types.ChannelId(101))
	childSource := e2e.OpenE2EChannel(cross(cur), types.ChannelId(102))

	forward := z.Forward{
		Path:             e2e.ForwardPath(cross(cur), uint32(parentChannel), uint32(childSource)),
		TimeoutTimestamp: 999,
		Instruction: e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"),
			ContractCalldata: []byte("forward-core-frame"),
		}),
	}
	packet := core.NewPacket(types.ChannelId(1), parentChannel,
		e2e.MustPacketData(cross(cur), e2e.MustForwardInstruction(cross(cur), forward)), types.Timestamp(0))

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, nil, 1))

	expectedChild := e2e.MustForwardChildPacket(cross(cur), packet, u256.Zero(), [32]byte{}, forward)
	_, inFlight := zkgm.GetInFlightPacket(zkgm.NewInFlightKey(cross(cur), types.MustCommit(types.CommitPacket(expectedChild))))

	println("impl_path", zkgm.ImplPath())
	println("child_source", expectedChild.SourceChannelId.String())
	println("child_destination", expectedChild.DestinationChannelId.String())
	println("in_flight", inFlight)
	println("parent_ack", core.HasAcknowledgement(cross(cur), packet))
	println("forward_allowedimpls_positive", "ok")
}

// Output:
// impl_path gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1
// child_source 2
// child_destination 102
// in_flight true
// parent_ack false
// forward_allowedimpls_positive ok
