package core

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/types"
)

// PacketSend commits a packet for the caller's port. Per the ibc-union-spec the
// timeout height is always zero (types.MustBeZero); only the timeout timestamp is
// meaningful.
func PacketSend(cur realm, sourceChannelId types.ChannelId, timeoutTimestamp types.Timestamp, data []byte) types.Packet {
	portId := store.getChannelOwner(sourceChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedPacketSender)
	}

	channel := store.getChannel(sourceChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)

	packet := types.Packet{
		SourceChannelId:      sourceChannelId,
		DestinationChannelId: channel.CounterpartyChannelId,
		Data:                 data,
		TimeoutHeight:        0,
		TimeoutTimestamp:     timeoutTimestamp,
	}
	store.clientForChannel(sourceChannelId).commitPacket(packet)

	emitPacketSendEvent(packet, channel, connection)
	return packet
}

func PacketRecv(cur realm, msg types.MsgPacketRecv) {
	relayer := cur.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	firstChannel := store.getChannel(first.DestinationChannelId)
	firstConnection := ensureConnectionOpen(firstChannel.ConnectionId)
	batchKey := types.BatchPacketsPath(commitPacketsHash(msg.Packets))
	verifyMembershipActive(firstConnection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, batchKey[:], h256Bytes(types.COMMITMENT_MAGIC))
	c := store.clientForChannel(first.DestinationChannelId)
	now := nowNanos()

	for i, packet := range msg.Packets {
		channel, skip := acceptRecvPacket(c, packet, first.DestinationChannelId, now)
		if skip {
			continue
		}

		var relayerMsg []byte
		if i < len(msg.RelayerMsgs) {
			relayerMsg = msg.RelayerMsgs[i]
		}

		portId := store.getChannelOwner(packet.DestinationChannelId)
		res := store.getAppByPortId(portId).OnRecvPacket(cross(cur), packet, relayer, relayerMsg)
		if err := commitSyncAck(c, packet, channel, firstConnection, res); err != nil {
			panic(err)
		}

		emitPacketRecvEvent(PacketRecvEvent, packet, channel, firstConnection, "maker_msg", relayerMsg)
	}
}

func IntentPacketRecv(cur realm, msg types.MsgIntentPacketRecv) {
	marketMaker := cur.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}

	first := msg.Packets[0]
	firstChannel := store.getChannel(first.DestinationChannelId)
	firstConnection := ensureConnectionOpen(firstChannel.ConnectionId)
	portId := store.getChannelOwner(first.DestinationChannelId)
	intentApp, ok := store.getAppByPortId(portId).(app.IIntentApp)
	if !ok {
		panic(ErrIntentNotSupported)
	}
	c := store.clientForChannel(first.DestinationChannelId)
	now := nowNanos()

	for i, packet := range msg.Packets {
		channel, skip := acceptRecvPacket(c, packet, first.DestinationChannelId, now)
		if skip {
			continue
		}

		var marketMakerMsg []byte
		if i < len(msg.MarketMakerMessages) {
			marketMakerMsg = msg.MarketMakerMessages[i]
		}

		res := intentApp.OnIntentRecvPacket(cross(cur), packet, marketMaker, marketMakerMsg)
		if err := commitSyncAck(c, packet, channel, firstConnection, res); err != nil {
			panic(err)
		}

		emitPacketRecvEvent(IntentPacketRecvEvent, packet, channel, firstConnection, "market_maker_msg", marketMakerMsg)
	}
}

func PacketAcknowledgement(cur realm, msg types.MsgPacketAcknowledgement) {
	relayer := cur.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	if len(msg.Packets) != len(msg.Acknowledgements) {
		panic(ErrAcknowledgementCountMismatch)
	}

	first := msg.Packets[0]
	channel := store.getChannel(first.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)
	batchHash := commitPacketsHash(msg.Packets)
	key := types.BatchReceiptsPath(batchHash)
	value := types.CommitAcks(msg.Acknowledgements)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, key[:], value[:])

	c := store.clientForChannel(first.SourceChannelId)
	processed := false
	for i, packet := range msg.Packets {
		// Validate same channel before the commitment check so that a mixed-channel
		// batch is always rejected, not silently skipped.
		if packet.SourceChannelId != first.SourceChannelId {
			panic(ErrBatchSameChannelOnly)
		}
		if !c.hasPacketCommitment(packet) {
			continue
		}

		ack := msg.Acknowledgements[i]
		portId := store.getChannelOwner(packet.SourceChannelId)
		c.deletePacketCommitment(packet)
		processed = true
		store.getAppByPortId(portId).OnAcknowledgementPacket(cross(cur), packet, ack, relayer)

		emitPacketAckEvent(packet, channel, connection, ack)
	}
	if processed {
		c.deleteBatchPackets(batchHash)
	}
}

func PacketTimeout(cur realm, msg types.MsgPacketTimeout) {
	relayer := cur.Previous().Address()
	packet := msg.Packet

	// Safe lookup: absent channel or client means no commitment, nothing to do.
	entry, ok := store.getChannelEntry(packet.SourceChannelId)
	if !ok {
		return
	}
	c := store.getClient(entry.clientId)
	if c == nil || !c.hasPacketCommitment(packet) {
		return
	}

	channel := store.getChannel(packet.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	// ICS-04: if TimeoutTimestamp is set, reject before proof verification
	// unless the consensus time at ProofHeight is past the timeout.
	if packet.TimeoutTimestamp == 0 {
		panic(ErrPacketTimeoutNotReached)
	}
	proofTimestamp, err := c.lightClient.GetTimestampAtHeight(msg.ProofHeight)
	if err != nil {
		panic(err)
	}
	if proofTimestamp <= packet.TimeoutTimestamp {
		panic(ErrPacketTimeoutNotReached)
	}

	key := types.BatchReceiptsPath(commitPacketHash(packet))
	verifyNonMembershipWithActiveClient(c, types.NewHeight(msg.ProofHeight), msg.Proof, key[:])

	portId := store.getChannelOwner(packet.SourceChannelId)
	c.deletePacketCommitment(packet)
	store.getAppByPortId(portId).OnTimeoutPacket(cross(cur), packet, relayer)

	emitPacketTimeoutEvent(packet, channel, connection)
}

func BatchSend(cur realm, msg types.MsgBatchSend) types.H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	portId := store.getChannelOwner(first.SourceChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedPacketSender)
	}
	for _, packet := range msg.Packets {
		if packet.SourceChannelId != first.SourceChannelId {
			panic(ErrBatchSameChannelOnly)
		}
	}
	c := store.clientForChannel(first.SourceChannelId)
	batchHash := commitPacketsHash(msg.Packets)
	c.saveBatchPackets(batchHash, types.COMMITMENT_MAGIC)
	// In-memory per-packet membership keeps HasPacketCommitment and the
	// PacketAcknowledgement / PacketTimeout cleanup paths working for
	// single-packet sends; multi-packet batches still commit at the batch
	// path on chain.
	for _, packet := range msg.Packets {
		c.setBatchPackets(commitPacketHash(packet), types.COMMITMENT_MAGIC)
	}
	channel := store.getChannel(first.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)
	emitBatchSendEvent(batchHash, first, channel, connection)
	return batchHash
}

func BatchAcks(cur realm, msg types.MsgBatchAcks) types.H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	if len(msg.Packets) != len(msg.Acks) {
		panic(ErrAcknowledgementCountMismatch)
	}
	first := msg.Packets[0]
	portId := store.getChannelOwner(first.DestinationChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedAckWriter)
	}
	c := store.clientForChannel(first.DestinationChannelId)
	for _, packet := range msg.Packets {
		if packet.DestinationChannelId != first.DestinationChannelId {
			panic(ErrBatchSameChannelOnly)
		}
		if !c.hasPacketReceipt(packet) {
			panic(ErrPacketReceiptNotFound)
		}
		if c.hasAcknowledgement(packet) {
			panic(ErrAcknowledgementAlreadyWritten)
		}
	}
	batchHash := commitPacketsHash(msg.Packets)
	ackHash := types.CommitAcks(msg.Acks)
	channel := store.getChannel(first.DestinationChannelId)
	connection, ok := store.getConnection(channel.ConnectionId)
	if !ok {
		panic("connection " + channel.ConnectionId.String() + " not found")
	}
	c.saveBatchReceipts(batchHash, ackHash)
	emitBatchAcksEvent(batchHash, ackHash, first, channel, connection)
	return batchHash
}

// WriteAcknowledgement commits an acknowledgement for a previously received
// packet. Async acknowledgement ownership is protocol-managed: core does not
// track pending async acknowledgement state.
func WriteAcknowledgement(cur realm, msg types.MsgWriteAcknowledgement) {
	portId := store.getChannelOwner(msg.Packet.DestinationChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedAckWriter)
	}

	if len(msg.Acknowledgement) == 0 {
		panic(ErrAcknowledgementEmpty)
	}

	c := store.clientForChannel(msg.Packet.DestinationChannelId)
	if !c.hasPacketReceipt(msg.Packet) {
		panic(ErrPacketReceiptNotFound)
	}

	if c.hasAcknowledgement(msg.Packet) {
		panic(ErrAcknowledgementAlreadyWritten)
	}

	channel := store.getChannel(msg.Packet.DestinationChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	c.commitAcknowledgement(msg.Packet, msg.Acknowledgement)

	emitWriteAckEvent(msg.Packet, channel, connection, msg.Acknowledgement)
}

// acceptRecvPacket validates recv-path invariants and records a packet
// receipt. Receipts serve as both replay protection and the source-side
// timeout signal.
func acceptRecvPacket(c *client, packet types.Packet, batchChannelId types.ChannelId, now uint64) (types.Channel, bool) {
	channel := store.getChannel(packet.DestinationChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	if packet.DestinationChannelId != batchChannelId {
		panic(ErrBatchSameChannelOnly)
	}

	// Ignore duplicate packets so batch retries remain idempotent.
	if c.hasPacketReceipt(packet) {
		return channel, true
	}

	// Do not execute packets that have already timed out on the source chain.
	if packet.TimeoutTimestamp != 0 && now >= uint64(packet.TimeoutTimestamp) {
		panic(ErrPacketTimeoutExpired)
	}

	c.setPacketReceipt(packet)
	return channel, false
}

// commitSyncAck records non-async recv results as Union receipt evidence.
// Sync success and failure results must carry a non-empty acknowledgement.
func commitSyncAck(c *client, packet types.Packet, channel types.Channel, connection types.Connection, res types.RecvPacketResult) error {
	switch res.Status {
	case types.PacketStatusAsync:
	case types.PacketStatusSuccess, types.PacketStatusFailure:
		if len(res.Acknowledgement) == 0 {
			return ErrSyncAckEmpty
		}
		c.commitAcknowledgement(packet, res.Acknowledgement)
		emitWriteAckEvent(packet, channel, connection, res.Acknowledgement)
	default:
		return ErrUnknownPacketStatus
	}
	return nil
}
