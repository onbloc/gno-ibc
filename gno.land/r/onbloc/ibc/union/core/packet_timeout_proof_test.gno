package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// ICS-04: PacketTimeout must reject proofs whose consensus timestamp has not
// passed packet.TimeoutTimestamp.

func TestPacketTimeoutRejectsProofBeforeTimeout(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	client := st.clientRegistry[mockType].(*mockClient)
	client.timestamp = types.Timestamp(500)
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(1000),
	}
	st.commitPacket(packet)

	uassert.AbortsContains(t, cur, "packet timeout not reached", func(cur realm) {
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
	})
	if !st.hasPacketCommitment(packet) {
		t.Fatal("rejected timeout must not delete the source commitment")
	}
	// Cheap timestamp check must precede the proof verification so a
	// malicious early-proof never pays the Merkle-verify gas cost.
	if len(client.nonMembershipKeys) != 0 {
		t.Fatal("VerifyNonMembership must not run when timestamp check rejects")
	}
}

// Boundary: spec requires `proofHeight.timestamp > packet.timeoutTimestamp`,
// so equality must also be rejected.
func TestPacketTimeoutRejectsProofAtBoundary(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	client := st.clientRegistry[mockType].(*mockClient)
	client.timestamp = types.Timestamp(1000)
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(1000),
	}
	st.commitPacket(packet)

	uassert.AbortsContains(t, cur, "packet timeout not reached", func(cur realm) {
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
	})
	if !st.hasPacketCommitment(packet) {
		t.Fatal("rejected timeout must not delete the source commitment")
	}
}

// TimeoutTimestamp == 0 means "no deadline" (recv-side uses the same
// convention), so PacketTimeout must refuse such packets outright.
func TestPacketTimeoutRejectsZeroTimeoutPacket(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	client := st.clientRegistry[mockType].(*mockClient)
	client.timestamp = types.Timestamp(1 << 62) // any positive proof timestamp
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     0,
	}
	st.commitPacket(packet)

	uassert.AbortsContains(t, cur, "packet timeout not reached", func(cur realm) {
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
	})
	if !st.hasPacketCommitment(packet) {
		t.Fatal("zero-timeout packet must keep its commitment")
	}
	if len(client.nonMembershipKeys) != 0 {
		t.Fatal("VerifyNonMembership must not run for zero-timeout packets")
	}
}

func TestPacketTimeoutAcceptsProofAfterTimeout(cur realm, t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	client := st.clientRegistry[mockType].(*mockClient)
	client.timestamp = types.Timestamp(2000)
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(1000),
	}
	st.commitPacket(packet)

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketTimeout(cur, types.MsgPacketTimeout{Packet: packet})
	})
	if st.hasPacketCommitment(packet) {
		t.Fatal("successful timeout must delete the source commitment")
	}
}
