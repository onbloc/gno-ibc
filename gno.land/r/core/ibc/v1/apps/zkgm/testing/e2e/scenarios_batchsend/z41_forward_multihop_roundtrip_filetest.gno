// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	u256 "gno.land/p/gnoswap/uint256"

	z "gno.land/p/onbloc/ibc/zkgm"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	"gno.land/r/onbloc/unionibc/v1/core"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
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
			ContractCalldata: []byte("forward-roundtrip"),
		}),
	}
	parent := core.NewPacket(cross(cur), parentChannel, parentChannel,
		e2e.MustPacketData(cross(cur), e2e.MustForwardInstruction(cross(cur), forward)), 0, core.Timestamp(0))
	child := e2e.MustForwardChildPacket(cross(cur), parent, u256.Zero(), [32]byte{}, forward)
	childKey := zkgm.NewInFlightKey(cross(cur), core.CommitPacket(child))

	println("[SCENARIO] 1. forward recv creates child and defers parent ack")
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{parent}, nil, nil, core.Height(1)))
	_, inFlight := zkgm.GetInFlightPacket(childKey)
	println("impl_path", zkgm.ImplPath())
	println("child_source", child.SourceChannelId.String())
	println("child_destination", child.DestinationChannelId.String())
	println("child_commitment_before_ack", core.HasPacketCommitment(cross(cur), child))
	println("in_flight_before_ack", inFlight)
	println("parent_ack_before_ack", core.HasAcknowledgement(cross(cur), parent))

	println("")
	println("[SCENARIO] 2. child ack propagates to parent")
	childAck := e2e.MustCallAck(cross(cur))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement(cross(cur), []core.Packet{child}, [][]byte{childAck}, nil, core.Height(1)))
	_, inFlight = zkgm.GetInFlightPacket(childKey)
	println("child_commitment_after_ack", core.HasPacketCommitment(cross(cur), child))
	println("in_flight_after_ack", inFlight)
	println("parent_ack_after_ack", core.HasAcknowledgement(cross(cur), parent))
	println("parent_ack_matches_child_ack", core.AcknowledgementHash(cross(cur), parent).String() == core.CommitAcks([][]byte{childAck}).String())
	println("forward_multihop_roundtrip", "ok")
}

// Output:
// [SCENARIO] 1. forward recv creates child and defers parent ack
// impl_path gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
// child_source 2
// child_destination 102
// child_commitment_before_ack true
// in_flight_before_ack true
// parent_ack_before_ack false
//
// [SCENARIO] 2. child ack propagates to parent
// child_commitment_after_ack false
// in_flight_after_ack false
// parent_ack_after_ack true
// parent_ack_matches_child_ack true
// forward_multihop_roundtrip ok
