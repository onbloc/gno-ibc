package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// Converted from Union send_packet_ok.
// Gno equivalent surface: SendPacket. Union asserts execute(...).is_ok().
// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L20-L76
func TestUnionSendPacketOK(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)

	data := []byte{0, 1, 2}
	timeout := types.Timestamp(1000000)
	uassert.NotAborts(t, cur, func(cur realm) {
		SendPacket(cross(cur), channelId, timeout, data)
	})
}

// Converted from Union send_packet_missing_timeout.
// Gno equivalent surface: SendPacket. Union expects ContractError::TimeoutMustBeSet.
// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L79-L136
func TestUnionSendPacketMissingTimeout(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)

	uassert.AbortsContains(t, cur, "timeout must be set", func(cur realm) {
		SendPacket(cross(cur), channelId, 0, []byte{0, 1, 2})
	})
}

// Converted from Union send_packet_channel_does_not_exist.
// Gno equivalent surface: SendPacket. Union expects a generic storage error.
// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L139-L201
func TestUnionSendPacketChannelDoesNotExist(cur realm, t *testing.T) {
	resetStore(cur)
	setupOpenChannel(t)

	uassert.AbortsContains(t, cur, "channel 3 not found", func(cur realm) {
		SendPacket(cross(cur), types.ChannelId(3), 1000000, []byte{0, 1, 2})
	})
}

// Converted from Union send_packet_module_is_not_channel_owner.
// Gno equivalent surface: SendPacket. Union expects ContractError::Unauthorized.
// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L204-L261
func TestUnionSendPacketModuleIsNotChannelOwner(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	setChannelOwner(channelId, "g1notchannelowner")

	uassert.AbortsContains(t, cur, "caller not authorized to send packet", func(cur realm) {
		SendPacket(cross(cur), channelId, 1000000, []byte{0, 1, 2})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1605-L1736
func TestUnionBatchSendOK(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	timeout := types.Timestamp(248)
	p1 := SendPacket(cross(cur), channelId, timeout, []byte{1, 2, 3})
	p2 := SendPacket(cross(cur), channelId, timeout, []byte{4, 5, 6})

	uassert.NotAborts(t, cur, func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p2, p1}})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1740-L1843
func TestUnionBatchSendPacketNotSent(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes{4, 5, 6}, TimeoutTimestamp: 0}
	p2 := types.Packet{SourceChannelId: channelId, DestinationChannelId: 99, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: 0}

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		BatchSend(cross(cur), types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1846-L2027
func TestUnionBatchAcksOK(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{3, 4, 5}, TimeoutTimestamp: testFutureTimeoutNanos}
	store.commitAcknowledgement(p1, []byte{1})
	store.commitAcknowledgement(p2, []byte{1})

	uassert.NotAborts(t, cur, func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{
			Packets: []types.Packet{p1, p2},
			Acks:    [][]byte{{1}, {1}},
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L2031-L2134
func TestUnionBatchAcksPacketNotReceived(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{3, 4, 5}, TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{
			Packets: []types.Packet{p1, p2},
			Acks:    [][]byte{{1}, {1}},
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L2138-L2319
func TestUnionBatchAcksTamperedPacket(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	p1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}
	p2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{3, 4, 5}, TimeoutTimestamp: testFutureTimeoutNanos}
	tampered1 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{10, 20, 30}, TimeoutTimestamp: testFutureTimeoutNanos}
	tampered2 := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{30, 40, 50}, TimeoutTimestamp: testFutureTimeoutNanos}
	store.commitAcknowledgement(p1, []byte{1})
	store.commitAcknowledgement(p2, []byte{1})

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		BatchAcks(cross(cur), types.MsgBatchAcks{
			Packets: []types.Packet{tampered1, tampered2},
			Acks:    [][]byte{{1}, {1}},
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L307-L329
func TestUnionRecvPacketOK(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes{1, 2, 3},
		TimeoutTimestamp:     testFutureTimeoutNanos,
	}

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{
			Packets:     []types.Packet{packet},
			RelayerMsgs: [][]byte{{1}},
			Relayer:     testutils.TestAddress("union-relayer"),
			Proof:       []byte{1, 2, 3},
			ProofHeight: 1,
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L376-L405
func TestUnionRecvPacketInvalidChannelState(cur realm, t *testing.T) {
	resetStore(cur)
	setupOpenChannel(t)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: 5,
		Data:                 types.Bytes{1, 2, 3},
		TimeoutTimestamp:     testFutureTimeoutNanos,
	}

	uassert.AbortsContains(t, cur, "channel 5 not found", func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{
			Packets:     []types.Packet{packet},
			RelayerMsgs: [][]byte{{1}},
			Relayer:     testutils.TestAddress("union-relayer"),
			Proof:       []byte{1, 2, 3},
			ProofHeight: 1,
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L456-L478
func TestUnionRecvPacketTimeoutTimestamp(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes{1, 2, 3},
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{
			Packets:     []types.Packet{packet},
			RelayerMsgs: [][]byte{{1}},
			Relayer:     testutils.TestAddress("union-relayer"),
			Proof:       []byte{1, 2, 3},
			ProofHeight: 1,
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1119-L1238
func TestUnionWriteAcknowledgementOK(cur realm, t *testing.T) {
	resetStore(cur)
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{
		Packets:     []types.Packet{packet},
		RelayerMsgs: [][]byte{{1}},
		Relayer:     testutils.TestAddress("union-relayer"),
		Proof:       []byte{1, 2, 3},
		ProofHeight: 1,
	})
	uassert.NotAborts(t, cur, func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte{1},
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1242-L1361
func TestUnionWriteAcknowledgementModuleIsNotChannelOwner(cur realm, t *testing.T) {
	resetStore(cur)
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{
		Packets:     []types.Packet{packet},
		RelayerMsgs: [][]byte{{1}},
		Relayer:     testutils.TestAddress("union-relayer"),
		Proof:       []byte{1, 2, 3},
		ProofHeight: 1,
	})
	setChannelOwner(channelId, "gno.land/r/not/channel-owner")

	uassert.AbortsContains(t, cur, "caller not authorized to write ack", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte{1},
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1365-L1459
func TestUnionWriteAcknowledgementPacketNotReceived(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet receipt not found", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte{1},
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1463-L1601
func TestUnionWriteAcknowledgementAlreadyExists(cur realm, t *testing.T) {
	resetStore(cur)
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	app.recvResult = NewRecvPacketResult(types.PacketStatusAsync, nil)
	packet := types.Packet{SourceChannelId: 99, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}

	PacketRecv(cross(cur), types.MsgPacketRecv{
		Packets:     []types.Packet{packet},
		RelayerMsgs: [][]byte{{1}},
		Relayer:     testutils.TestAddress("union-relayer"),
		Proof:       []byte{1, 2, 3},
		ProofHeight: 1,
	})
	WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
		Packet:          packet,
		Acknowledgement: []byte{1},
	})

	uassert.AbortsContains(t, cur, "acknowledgement already written", func(cur realm) {
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          packet,
			Acknowledgement: []byte{1},
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L525-L547
func TestUnionRecvIntentPacketOK(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes{1, 2, 3},
		TimeoutTimestamp:     testFutureTimeoutNanos,
	}

	uassert.NotAborts(t, cur, func(cur realm) {
		IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{
			Packets:             []types.Packet{packet},
			MarketMakerMessages: [][]byte{{1, 2, 3}},
			MarketMaker:         testutils.TestAddress("marketmaker"),
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L594-L616
func TestUnionRecvIntentPacketTimeoutTimestamp(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes{1, 2, 3},
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}

	uassert.AbortsContains(t, cur, "packet timeout expired", func(cur realm) {
		IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{
			Packets:             []types.Packet{packet},
			MarketMakerMessages: [][]byte{{1, 2, 3}},
			MarketMaker:         testutils.TestAddress("marketmaker"),
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L706-L728
func TestUnionAcknowledgePacketOK(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}
	store.commitPacket(packet)

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
			Packets:          []types.Packet{packet},
			Acknowledgements: [][]byte{{1, 2, 3}},
			Proof:            []byte{1},
			ProofHeight:      1,
			Relayer:          testutils.TestAddress("union-relayer"),
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L818-L840
func TestUnionAcknowledgePacketTampered(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	sent := types.Packet{SourceChannelId: channelId, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}
	tampered := types.Packet{SourceChannelId: channelId, DestinationChannelId: channelId, Data: types.Bytes{4, 1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}
	store.commitPacket(sent)

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
			Packets:          []types.Packet{tampered},
			Acknowledgements: [][]byte{{1, 2, 3}},
			Proof:            []byte{1},
			ProofHeight:      1,
			Relayer:          testutils.TestAddress("union-relayer"),
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L917-L939
func TestUnionAcknowledgePacketNotSent(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: testFutureTimeoutNanos}

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{
			Packets:          []types.Packet{packet},
			Acknowledgements: [][]byte{{1, 2, 3}},
			Proof:            []byte{1},
			ProofHeight:      1,
			Relayer:          testutils.TestAddress("union-relayer"),
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L943-L1029
func TestUnionTimeoutPacketTimestampOK(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	timeout := types.Timestamp(64)
	client.timestamp = 100000
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: timeout}
	store.commitPacket(packet)

	uassert.NotAborts(t, cur, func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{
			Packet:      packet,
			Proof:       []byte{1},
			ProofHeight: 11,
			Relayer:     testutils.TestAddress("union-relayer"),
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/tests/channel/ibc_packet.rs#L1031-L1115
func TestUnionTimeoutPacketTimestampNotReached(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	timeout := types.Timestamp(248)
	client.timestamp = 128
	packet := types.Packet{SourceChannelId: channelId, DestinationChannelId: channelId, Data: types.Bytes{1, 2, 3}, TimeoutTimestamp: timeout}
	store.commitPacket(packet)

	uassert.AbortsContains(t, cur, "packet timeout not reached", func(cur realm) {
		PacketTimeout(cross(cur), types.MsgPacketTimeout{
			Packet:      packet,
			Proof:       []byte{1},
			ProofHeight: 11,
			Relayer:     testutils.TestAddress("union-relayer"),
		})
	})
}
