package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Far in the future relative to the gno test default block time
// (Unix=1234567890 sec ≈ 1.23e18 ns). Year ≈ 2116 in nanoseconds.
const testFutureTimeoutNanos Timestamp = 1 << 62

// ICS-04: destination must reject a packet whose TimeoutTimestamp is at or
// before its current block time.
func TestPacketRecvRejectsExpiredPacket(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)

	expired := Timestamp(nowNanos() - 1)
	packet := Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 Bytes("transfer"),
		TimeoutTimestamp:     expired,
	}

	uassert.AbortsContains(t, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})

	if st.hasPacketReceipt(packet) {
		t.Fatal("expired packet must not set a receipt")
	}
}

// TestPacketRecvRejectsBoundaryTimeout — the spec requires
// `consensusState.timestamp < packet.timeoutTimestamp`, so equality
// (now == timeout) must also be rejected.
func TestPacketRecvRejectsBoundaryTimeout(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)

	boundary := Timestamp(nowNanos())
	packet := Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 Bytes("transfer"),
		TimeoutTimestamp:     boundary,
	}

	uassert.AbortsContains(t, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})
}

// TestPacketRecvAcceptsZeroTimeout — TimeoutTimestamp == 0 means "no timeout".
func TestPacketRecvAcceptsZeroTimeout(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 Bytes("transfer"),
		TimeoutTimestamp:     0,
	}

	uassert.NotAborts(t, func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})
	if !st.hasPacketReceipt(packet) {
		t.Fatal("zero-timeout packet must be processed")
	}
}

// TestPacketRecvBatchRejectsIfAnyExpired — a batch containing one expired
// packet must abort. Receipts written for earlier packets within the same
// transaction will be rolled back by the panic.
func TestPacketRecvBatchRejectsIfAnyExpired(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	live := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	expired := Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: Bytes("b"), TimeoutTimestamp: Timestamp(nowNanos() - 1)}

	uassert.AbortsContains(t, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{live, expired}})
	})
}

// TestPacketRecvSkipsTimeoutCheckForExistingReceipt — if a receipt is already
// present (replay path), the recv loop must continue silently instead of
// aborting on a now-expired timestamp. Honest relayers re-submitting a batch
// after the timeout passes should not break.
func TestPacketRecvSkipsTimeoutCheckForExistingReceipt(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	// Receipt already written; timeout is now in the past.
	packet := Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 Bytes("replay"),
		TimeoutTimestamp:     Timestamp(nowNanos() - 1),
	}
	st.setPacketReceipt(packet)

	uassert.NotAborts(t, func(cur realm) {
		PacketRecv(cur, MsgPacketRecv{Packets: []Packet{packet}})
	})
}

// TestIntentPacketRecvRejectsExpiredPacket — market-maker fast-path must also
// refuse expired packets; otherwise a maker pays out a packet that the source
// chain can subsequently claim via timeout.
func TestIntentPacketRecvRejectsExpiredPacket(t *testing.T) {
	resetState()
	_, _, channelId := setupOpenChannel(t)
	packet := Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 Bytes("intent"),
		TimeoutTimestamp:     Timestamp(nowNanos() - 1),
	}

	uassert.AbortsContains(t, "packet timeout expired", func(cur realm) {
		IntentPacketRecv(cur, MsgIntentPacketRecv{Packets: []Packet{packet}})
	})
}
