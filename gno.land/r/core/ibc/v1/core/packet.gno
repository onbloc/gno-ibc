package core

import (
	"chain/runtime"
	"time"
)

// nowNanos returns the current block time in nanoseconds. Used for ICS-04
// packet timeout enforcement on the receive path.
func nowNanos() uint64 { return uint64(time.Now().UnixNano()) }

func PacketSend(_ realm, sourceChannelId ChannelId, timeoutHeight Height, timeoutTimestamp Timestamp, data []byte) Packet {
	portId := st.getChannelOwner(sourceChannelId)
	if string(portId) != runtime.PreviousRealm().PkgPath() {
		panic(ErrUnauthorizedPacketSender)
	}

	channel := st.getChannel(sourceChannelId)
	if channel.State != ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)

	packet := Packet{
		SourceChannelId:      sourceChannelId,
		DestinationChannelId: channel.CounterpartyChannelId,
		Data:                 data,
		TimeoutHeight:        timeoutHeight,
		TimeoutTimestamp:     timeoutTimestamp,
	}
	st.commitPacket(packet)

	emitPacketSendEvent(packet, channel, connection)
	return packet
}

// acceptRecvPacket validates packet against the recv-batch invariants and
// records its receipt. It returns the destination channel and whether the packet
// should be skipped because its receipt already exists.
func acceptRecvPacket(packet Packet, batchChannelId ChannelId, now uint64) (Channel, bool) {
	channel := st.getChannel(packet.DestinationChannelId)
	if channel.State != ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	if packet.DestinationChannelId != batchChannelId {
		panic(ErrBatchSameChannelOnly)
	}

	// Receipt presence is the replay-protection signal: skip silently so
	// honest relayers can re-submit batches without aborting the whole tx.
	if st.hasPacketReceipt(packet) {
		return channel, true
	}

	// Reject a packet already past its source-side timeout so it cannot be
	// executed on the destination after a successful source-side timeout.
	if packet.TimeoutTimestamp != 0 && now >= uint64(packet.TimeoutTimestamp) {
		panic(ErrPacketTimeoutExpired)
	}

	st.setPacketReceipt(packet)
	return channel, false
}

func PacketRecv(_ realm, msg MsgPacketRecv) {
	relayer := runtime.OriginCaller()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	firstChannel := st.getChannel(first.DestinationChannelId)
	firstConnection := ensureConnectionOpen(firstChannel.ConnectionId)
	batchKey := BatchPacketsPath(CommitPackets(msg.Packets))
	st.getClient(firstConnection.ClientId).VerifyMembership(
		firstConnection.ClientId, msg.ProofHeight, msg.Proof, batchKey[:], h256Bytes(COMMITMENT_MAGIC),
	)
	now := nowNanos()

	for i, packet := range msg.Packets {
		channel, skip := acceptRecvPacket(packet, first.DestinationChannelId, now)
		if skip {
			continue
		}

		var relayerMsg []byte
		if i < len(msg.RelayerMsgs) {
			relayerMsg = msg.RelayerMsgs[i]
		}
		portId := st.getChannelOwner(packet.DestinationChannelId)
		res := st.getAppByPortId(portId).OnRecvPacket(packet, relayer, relayerMsg)
		switch res.Status {
		case PacketStatusAsync:
		case PacketStatusSuccess, PacketStatusFailure:
			if len(res.Ack) == 0 {
				panic(ErrSyncAckEmpty)
			}
			st.commitAcknowledgement(packet, res.Ack)
			emitWriteAckEvent(packet, channel, firstConnection, res.Ack)
		default:
			panic(ErrUnknownPacketStatus)
		}

		emitPacketRecvEvent(PacketRecvEvent, packet, channel, firstConnection, "maker_msg", relayerMsg)
	}
}

func IntentPacketRecv(_ realm, msg MsgIntentPacketRecv) {
	marketMaker := runtime.OriginCaller()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	now := nowNanos()

	for i, packet := range msg.Packets {
		channel, skip := acceptRecvPacket(packet, first.DestinationChannelId, now)
		if skip {
			continue
		}

		var marketMakerMsg []byte
		if i < len(msg.MarketMakerMessages) {
			marketMakerMsg = msg.MarketMakerMessages[i]
		}
		portId := st.getChannelOwner(packet.DestinationChannelId)
		st.getAppByPortId(portId).OnIntentRecvPacket(packet, marketMaker, marketMakerMsg)

		connection := ensureConnectionOpen(channel.ConnectionId)
		emitPacketRecvEvent(IntentPacketRecvEvent, packet, channel, connection, "market_maker_msg", marketMakerMsg)
	}
}

func PacketAcknowledgement(_ realm, msg MsgPacketAcknowledgement) {
	relayer := runtime.OriginCaller()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	if len(msg.Packets) != len(msg.Acknowledgements) {
		panic(ErrAcknowledgementCountMismatch)
	}
	first := msg.Packets[0]
	channel := st.getChannel(first.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)
	batchHash := CommitPackets(msg.Packets)
	key := BatchReceiptsPath(batchHash)
	value := CommitAcks(msg.Acknowledgements)
	st.getClient(connection.ClientId).VerifyMembership(
		connection.ClientId, msg.ProofHeight, msg.Proof, key[:], value[:],
	)

	processed := false
	for i, packet := range msg.Packets {
		if !st.hasPacketCommitment(packet) {
			continue
		}
		if packet.SourceChannelId != first.SourceChannelId {
			panic(ErrBatchSameChannelOnly)
		}

		ack := msg.Acknowledgements[i]
		portId := st.getChannelOwner(packet.SourceChannelId)
		st.getAppByPortId(portId).OnAcknowledgementPacket(packet, ack, relayer)

		st.deletePacketCommitment(packet)
		processed = true

		emitPacketAckEvent(packet, channel, connection, ack)
	}
	if processed {
		st.deleteBatchPackets(batchHash)
	}
}

func PacketTimeout(_ realm, msg MsgPacketTimeout) {
	relayer := runtime.OriginCaller()
	packet := msg.Packet
	if !st.hasPacketCommitment(packet) {
		return
	}

	channel := st.getChannel(packet.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	client := st.getClient(connection.ClientId)

	// ICS-04: if TimeoutTimestamp is set, reject before proof verification
	// unless the consensus time at ProofHeight is past the timeout.
	if packet.TimeoutTimestamp == 0 ||
		client.GetTimestamp(connection.ClientId, msg.ProofHeight) <= packet.TimeoutTimestamp {
		panic(ErrPacketTimeoutNotReached)
	}

	key := BatchReceiptsPath(CommitPacket(packet))
	client.VerifyNonMembership(connection.ClientId, msg.ProofHeight, msg.Proof, key[:])

	portId := st.getChannelOwner(packet.SourceChannelId)
	st.getAppByPortId(portId).OnTimeoutPacket(packet, relayer)

	st.deletePacketCommitment(packet)

	emitPacketTimeoutEvent(packet, channel, connection)
}

// HasPacketCommitment exposes packet commitment presence for filetests and
// lifecycle diagnostics.
func HasPacketCommitment(_ realm, packet Packet) bool {
	return st.hasPacketCommitment(packet)
}

// HasPacketReceipt exposes packet receipt presence for filetests and
// lifecycle diagnostics.
func HasPacketReceipt(_ realm, packet Packet) bool {
	return st.hasPacketReceipt(packet)
}

// HasAcknowledgement exposes packet acknowledgement presence for filetests and
// lifecycle diagnostics.
func HasAcknowledgement(_ realm, packet Packet) bool {
	return st.hasAcknowledgement(packet)
}

// AcknowledgementHash exposes the committed Union-spec acknowledgement hash
// (CommitAcks of the single ack) for filetests and lifecycle diagnostics.
func AcknowledgementHash(_ realm, packet Packet) H256 {
	return st.acknowledgementHash(packet)
}

func BatchSend(_ realm, msg MsgBatchSend) H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	portId := st.getChannelOwner(first.SourceChannelId)
	if string(portId) != runtime.PreviousRealm().PkgPath() {
		panic(ErrUnauthorizedPacketSender)
	}
	for _, packet := range msg.Packets {
		if packet.SourceChannelId != first.SourceChannelId {
			panic(ErrBatchSameChannelOnly)
		}
	}
	batchHash := CommitPackets(msg.Packets)
	st.saveBatchPackets(batchHash, COMMITMENT_MAGIC)
	// In-memory per-packet membership keeps HasPacketCommitment and the
	// PacketAcknowledgement / PacketTimeout cleanup paths working for
	// single-packet sends; multi-packet batches still commit at the batch
	// path on chain.
	for _, packet := range msg.Packets {
		st.setBatchPackets(CommitPacket(packet), COMMITMENT_MAGIC)
	}
	channel := st.getChannel(first.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)
	emitBatchSendEvent(batchHash, first, channel, connection)
	return batchHash
}

func BatchAcks(_ realm, msg MsgBatchAcks) H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	if len(msg.Packets) != len(msg.Acks) {
		panic(ErrAcknowledgementCountMismatch)
	}
	first := msg.Packets[0]
	portId := st.getChannelOwner(first.DestinationChannelId)
	if string(portId) != runtime.PreviousRealm().PkgPath() {
		panic(ErrUnauthorizedAckWriter)
	}
	for _, packet := range msg.Packets {
		if packet.DestinationChannelId != first.DestinationChannelId {
			panic(ErrBatchSameChannelOnly)
		}
	}
	batchHash := CommitPackets(msg.Packets)
	st.saveBatchReceipts(batchHash, CommitAcks(msg.Acks))
	return batchHash
}

func QueryBatchPackets(batchHash H256) string {
	value, ok := st.batchPackets[BatchPacketsPath(batchHash)]
	if !ok {
		return ""
	}
	return h256String(value)
}

func QueryBatchReceipts(batchHash H256) string {
	value, ok := st.batchReceipts[BatchReceiptsPath(batchHash)]
	if !ok {
		return ""
	}
	return h256String(value)
}

// QueryCommitmentAtPath reads st.batchPackets by an already-derived commitment
// path (e.g. BatchPacketsPath or per-packet PacketCommitmentPath output).
func QueryCommitmentAtPath(path H256) string {
	value, ok := st.batchPackets[path]
	if !ok {
		return ""
	}
	return h256String(value)
}

// QueryReceiptAtPath reads st.batchReceipts by an already-derived commitment path.
func QueryReceiptAtPath(path H256) string {
	value, ok := st.batchReceipts[path]
	if !ok {
		return ""
	}
	return h256String(value)
}

// WriteAcknowledgement commits an acknowledgement for a previously received
// packet. Async acknowledgement ownership is protocol-managed: core does not
// track pending async acknowledgement state.
func WriteAcknowledgement(_ realm, msg MsgWriteAcknowledgement) {
	portId := st.getChannelOwner(msg.Packet.DestinationChannelId)
	if string(portId) != runtime.PreviousRealm().PkgPath() {
		panic(ErrUnauthorizedAckWriter)
	}
	if len(msg.Acknowledgement) == 0 {
		panic(ErrAcknowledgementEmpty)
	}
	if st.hasAcknowledgement(msg.Packet) {
		panic(ErrAcknowledgementAlreadyWritten)
	}
	channel := st.getChannel(msg.Packet.DestinationChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	st.commitAcknowledgement(msg.Packet, msg.Acknowledgement)

	emitWriteAckEvent(msg.Packet, channel, connection, msg.Acknowledgement)
}
