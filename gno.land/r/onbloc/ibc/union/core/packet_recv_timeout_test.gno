package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// Far in the future relative to the gno test default block time
// (Unix=1234567890 sec ≈ 1.23e18 ns). Year ≈ 2116 in nanoseconds.
const testFutureTimeoutNanos types.Timestamp = 1 << 62

// ICS-04: destination must reject a packet whose TimeoutTimestamp is at or
// before its current block time.
func TestPacketRecvRejectsExpiredPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)

	expired := types.Timestamp(nowNanos() - 1)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     expired,
	}

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	})

	if store.hasPacketReceipt(packet) {
		t.Fatal("expired packet must not set a receipt")
	}
}

// TestPacketRecvRejectsBoundaryTimeout — the spec requires
// `consensusState.timestamp < packet.timeoutTimestamp`, so equality
// (now == timeout) must also be rejected.
func TestPacketRecvRejectsBoundaryTimeout(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)

	boundary := types.Timestamp(nowNanos())
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     boundary,
	}

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	})
}

func TestPacketRecvRejectsZeroTimeout(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     0,
	}

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	})
	if store.hasPacketReceipt(packet) {
		t.Fatal("zero-timeout packet must not set a receipt")
	}
}

// TestPacketRecvBatchRejectsIfAnyExpired — a batch containing one expired
// packet must abort. Receipts written for earlier packets within the same
// transaction will be rolled back by the panic.
func TestPacketRecvBatchRejectsIfAnyExpired(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	live := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("a"), TimeoutTimestamp: testFutureTimeoutNanos}
	expired := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes("b"), TimeoutTimestamp: types.Timestamp(nowNanos() - 1)}

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{live, expired}, RelayerMsgs: [][]byte{nil, nil}})
	})
}

func TestPacketRecvChecksTimeoutBeforeExistingReceiptSkip(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	// Receipt already written; timeout is now in the past.
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("replay"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}
	store.setPacketReceipt(packet)

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		PacketRecv(cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{nil}})
	})
}

// TestIntentPacketRecvRejectsExpiredPacket — market-maker fast-path must also
// refuse expired packets; otherwise a maker pays out a packet that the source
// chain can subsequently claim via timeout.
func TestIntentPacketRecvRejectsExpiredPacket(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("intent"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		IntentPacketRecv(cur, types.MsgIntentPacketRecv{Packets: []types.Packet{packet}, MarketMakerMessages: [][]byte{nil}})
	})
}
