package core

import (
	"time"

	"gno.land/p/onbloc/ibc/host"
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/types"
)

// nowNanos returns the current block time in nanoseconds. Used for ICS-04
// packet timeout enforcement on the receive path.
func nowNanos() uint64 { return uint64(time.Now().UnixNano()) }

// PacketSend commits a packet for the caller's port. Per the ibc-union-spec the
// timeout height is always zero (types.MustBeZero); only the timeout timestamp is
// meaningful.
func PacketSend(cur realm, sourceChannelId types.ChannelId, timeoutTimestamp types.Timestamp, data []byte) types.Packet {
	portId := st.getChannelOwner(sourceChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedPacketSender)
	}

	channel := st.getChannel(sourceChannelId)
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
	st.commitPacket(packet)

	emitPacketSendEvent(packet, channel, connection)
	return packet
}

// acceptRecvPacket validates recv-path invariants and records a packet
// receipt. Receipts serve as both replay protection and the source-side
// timeout signal.
func acceptRecvPacket(packet types.Packet, batchChannelId types.ChannelId, now uint64) (types.Channel, bool) {
	channel := st.getChannel(packet.DestinationChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	if packet.DestinationChannelId != batchChannelId {
		panic(ErrBatchSameChannelOnly)
	}

	// Ignore duplicate packets so batch retries remain idempotent.
	if st.hasPacketReceipt(packet) {
		return channel, true
	}

	// Do not execute packets that have already timed out on the source chain.
	if packet.TimeoutTimestamp != 0 && now >= uint64(packet.TimeoutTimestamp) {
		panic(ErrPacketTimeoutExpired)
	}

	st.setPacketReceipt(packet)
	return channel, false
}

// commitSyncAck records non-async recv results as Union receipt evidence.
// Sync success and failure results must carry a non-empty acknowledgement.
func commitSyncAck(packet types.Packet, channel types.Channel, connection types.Connection, res types.RecvPacketResult) error {
	switch res.Status {
	case types.PacketStatusAsync:
	case types.PacketStatusSuccess, types.PacketStatusFailure:
		if len(res.Acknowledgement) == 0 {
			return ErrSyncAckEmpty
		}
		st.commitAcknowledgement(packet, res.Acknowledgement)
		emitWriteAckEvent(packet, channel, connection, res.Acknowledgement)
	default:
		return ErrUnknownPacketStatus
	}
	return nil
}

func PacketRecv(cur realm, msg types.MsgPacketRecv) {
	relayer := cur.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	firstChannel := st.getChannel(first.DestinationChannelId)
	firstConnection := ensureConnectionOpen(firstChannel.ConnectionId)
	batchKey := host.BatchPacketsPath(commitPacketsHash(msg.Packets))
	verifyMembershipActive(firstConnection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, batchKey[:], h256Bytes(types.COMMITMENT_MAGIC))
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
		res := st.getAppByPortId(portId).OnRecvPacket(cross(cur), packet, relayer, relayerMsg)
		if err := commitSyncAck(packet, channel, firstConnection, res); err != nil {
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
	firstChannel := st.getChannel(first.DestinationChannelId)
	firstConnection := ensureConnectionOpen(firstChannel.ConnectionId)
	portId := st.getChannelOwner(first.DestinationChannelId)
	intentApp, ok := st.getAppByPortId(portId).(app.IIntentApp)
	if !ok {
		panic(ErrIntentNotSupported)
	}
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

		res := intentApp.OnIntentRecvPacket(cross(cur), packet, marketMaker, marketMakerMsg)
		if err := commitSyncAck(packet, channel, firstConnection, res); err != nil {
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
	channel := st.getChannel(first.SourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)
	batchHash := commitPacketsHash(msg.Packets)
	key := host.BatchReceiptsPath(batchHash)
	value := types.CommitAcks(msg.Acknowledgements)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, key[:], value[:])

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
		st.deletePacketCommitment(packet)
		processed = true
		st.getAppByPortId(portId).OnAcknowledgementPacket(cross(cur), packet, ack, relayer)

		emitPacketAckEvent(packet, channel, connection, ack)
	}
	if processed {
		st.deleteBatchPackets(batchHash)
	}
}

func PacketTimeout(cur realm, msg types.MsgPacketTimeout) {
	relayer := cur.Previous().Address()
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
		client.GetTimestamp(connection.ClientId, types.NewHeight(msg.ProofHeight)) <= packet.TimeoutTimestamp {
		panic(ErrPacketTimeoutNotReached)
	}

	key := host.BatchReceiptsPath(commitPacketHash(packet))
	verifyNonMembershipWithActiveClient(client, connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, key[:])

	portId := st.getChannelOwner(packet.SourceChannelId)
	st.deletePacketCommitment(packet)
	st.getAppByPortId(portId).OnTimeoutPacket(cross(cur), packet, relayer)

	emitPacketTimeoutEvent(packet, channel, connection)
}

// HasPacketCommitment exposes packet commitment presence for filetests and
// lifecycle diagnostics.
func HasPacketCommitment(_ realm, packet types.Packet) bool {
	return st.hasPacketCommitment(packet)
}

// HasPacketReceipt exposes packet receipt presence for filetests and
// lifecycle diagnostics.
func HasPacketReceipt(_ realm, packet types.Packet) bool {
	return st.hasPacketReceipt(packet)
}

// HasAcknowledgement exposes packet acknowledgement presence for filetests and
// lifecycle diagnostics.
func HasAcknowledgement(_ realm, packet types.Packet) bool {
	return st.hasAcknowledgement(packet)
}

// AcknowledgementHash exposes the committed Union-spec acknowledgement hash
// (types.CommitAcks of the single ack) for filetests and lifecycle diagnostics.
func AcknowledgementHash(_ realm, packet types.Packet) types.H256 {
	return st.acknowledgementHash(packet)
}

func BatchSend(cur realm, msg types.MsgBatchSend) types.H256 {
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	portId := st.getChannelOwner(first.SourceChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedPacketSender)
	}
	for _, packet := range msg.Packets {
		if packet.SourceChannelId != first.SourceChannelId {
			panic(ErrBatchSameChannelOnly)
		}
	}
	batchHash := commitPacketsHash(msg.Packets)
	st.saveBatchPackets(batchHash, types.COMMITMENT_MAGIC)
	// In-memory per-packet membership keeps HasPacketCommitment and the
	// PacketAcknowledgement / PacketTimeout cleanup paths working for
	// single-packet sends; multi-packet batches still commit at the batch
	// path on chain.
	for _, packet := range msg.Packets {
		st.setBatchPackets(commitPacketHash(packet), types.COMMITMENT_MAGIC)
	}
	channel := st.getChannel(first.SourceChannelId)
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
	portId := st.getChannelOwner(first.DestinationChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedAckWriter)
	}
	for _, packet := range msg.Packets {
		if packet.DestinationChannelId != first.DestinationChannelId {
			panic(ErrBatchSameChannelOnly)
		}
		if !st.hasPacketReceipt(packet) {
			panic(ErrPacketReceiptNotFound)
		}
		if st.hasAcknowledgement(packet) {
			panic(ErrAcknowledgementAlreadyWritten)
		}
	}
	batchHash := commitPacketsHash(msg.Packets)
	ackHash := types.CommitAcks(msg.Acks)
	channel := st.getChannel(first.DestinationChannelId)
	connection := st.getConnection(channel.ConnectionId)
	st.saveBatchReceipts(batchHash, ackHash)
	emitBatchAcksEvent(batchHash, ackHash, first, channel, connection)
	return batchHash
}

func QueryBatchPackets(batchHash types.H256) string {
	value, ok := st.batchPackets[host.BatchPacketsPath(batchHash)]
	if !ok {
		return ""
	}
	return h256String(value)
}

func QueryBatchReceipts(batchHash types.H256) string {
	value, ok := st.batchReceipts[host.BatchReceiptsPath(batchHash)]
	if !ok {
		return ""
	}
	return h256String(value)
}

// QueryCommitmentAtPath reads st.batchPackets by an already-derived commitment
// path (e.g. host.BatchPacketsPath or per-packet host.PacketCommitmentPath output).
func QueryCommitmentAtPath(path types.H256) string {
	value, ok := st.batchPackets[path]
	if !ok {
		return ""
	}
	return h256String(value)
}

// QueryReceiptAtPath reads st.batchReceipts by an already-derived commitment path.
func QueryReceiptAtPath(path types.H256) string {
	value, ok := st.batchReceipts[path]
	if !ok {
		return ""
	}
	return h256String(value)
}

// WriteAcknowledgement commits an acknowledgement for a previously received
// packet. Async acknowledgement ownership is protocol-managed: core does not
// track pending async acknowledgement state.
func WriteAcknowledgement(cur realm, msg types.MsgWriteAcknowledgement) {
	portId := st.getChannelOwner(msg.Packet.DestinationChannelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedAckWriter)
	}
	if len(msg.Acknowledgement) == 0 {
		panic(ErrAcknowledgementEmpty)
	}
	if !st.hasPacketReceipt(msg.Packet) {
		panic(ErrPacketReceiptNotFound)
	}
	if st.hasAcknowledgement(msg.Packet) {
		panic(ErrAcknowledgementAlreadyWritten)
	}
	channel := st.getChannel(msg.Packet.DestinationChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	st.commitAcknowledgement(msg.Packet, msg.Acknowledgement)

	emitWriteAckEvent(msg.Packet, channel, connection, msg.Acknowledgement)
}
