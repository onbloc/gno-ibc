package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// PacketTimeout follows Union ordering: verify destination non-membership and
// source packet commitment first, then reject if proof time has not reached
// packet.TimeoutTimestamp.

func TestPacketTimeoutRejectsProofBeforeTimeout(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.timestamp = types.Timestamp(500)
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(1000),
	}
	store.commitPacket(packet)

	uassert.AbortsContains(t, cur, "packet timeout not reached", func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	})
	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("VerifyNonMembership calls: got %d want 1", len(client.nonMembershipKeys))
	}
}

func TestPacketTimeoutAcceptsProofAtBoundary(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.timestamp = types.Timestamp(1000)
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(1000),
	}
	store.commitPacket(packet)

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	})
	if got, ok := store.clientForChannel(packet.SourceChannelId).getBatchPacketsAtPath(packetCommitmentPath(packet)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("timeout boundary marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
}

// TimeoutTimestamp == 0 means "no deadline" (recv-side uses the same
// convention), so PacketTimeout must refuse such packets outright.
func TestPacketTimeoutRejectsZeroTimeoutPacket(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.timestamp = types.Timestamp(1 << 62) // any positive proof timestamp
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     0,
	}
	store.commitPacket(packet)

	uassert.AbortsContains(t, cur, "timeout must be set", func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	})
	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("VerifyNonMembership calls: got %d want 1", len(client.nonMembershipKeys))
	}
}

func TestPacketTimeoutAcceptsProofAfterTimeout(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.timestamp = types.Timestamp(2000)
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(1000),
	}
	store.commitPacket(packet)

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	})
	if got, ok := store.clientForChannel(packet.SourceChannelId).getBatchPacketsAtPath(packetCommitmentPath(packet)); !ok || got != types.COMMITMENT_MAGIC_ACK {
		t.Fatalf("timeout marker: ok=%v got=%s want %s", ok, got, types.COMMITMENT_MAGIC_ACK)
	}
}

func TestPacketTimeoutRejectsMissingProofTimestamp(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.zeroTime = true
	packet := types.Packet{
		SourceChannelId:      channelId,
		DestinationChannelId: 99,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(1000),
	}
	store.commitPacket(packet)

	uassert.AbortsContains(t, cur, "packet timeout proof timestamp not found", func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{Packet: packet})
	})
	if len(client.nonMembershipKeys) != 0 {
		t.Fatalf("VerifyNonMembership calls: got %d want 0", len(client.nonMembershipKeys))
	}
}
