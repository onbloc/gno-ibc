package core

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/types"
)

// SendPacket commits a packet for the caller's port. Per the ibc-union-spec the
// timeout height is always zero (types.MustBeZero); only the timeout timestamp is
// meaningful.
func SendPacket(cur realm, sourceChannelId types.ChannelId, timeoutTimestamp types.Timestamp, data []byte) types.Packet {
	if timeoutTimestamp == 0 {
		panic(ErrTimeoutMustBeSet)
	}

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
	c := store.clientForChannel(sourceChannelId)
	if c.hasPacketCommitment(packet) {
		panic(ErrPacketCommitmentAlreadyExists)
	}
	c.commitPacket(packet)

	emitPacketSendEvent(packet, channel, connection)
	return packet
}

func PacketRecv(cur realm, msg types.MsgPacketRecv) {
	requireCanCall(0, cur, SelectorPacketRecv)

	relayer := cur.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}

	first := msg.Packets[0]
	destinationChannelId := first.DestinationChannelId
	channel := store.getChannel(destinationChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	proofCommitmentKey := types.BatchPacketsPath(commitPacketsHash(msg.Packets))
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, proofCommitmentKey[:], h256Bytes(types.COMMITMENT_MAGIC))

	portId := store.getChannelOwner(destinationChannelId)
	c := store.clientForChannel(destinationChannelId)
	now := nowNanos()

	for i, relayerMsg := range msg.RelayerMsgs {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		channel, skip := acceptRecvPacket(c, packet, destinationChannelId, now)
		if skip {
			continue
		}

		res := store.getAppByPortId(portId).OnRecvPacket(cross(cur), packet, relayer, relayerMsg)
		if err := commitSyncAck(c, packet, res); err != nil {
			panic(err)
		}

		emitPacketRecvEvent(PacketRecvEvent, packet, channel, connection, "maker_msg", relayerMsg)
	}
}

func IntentPacketRecv(cur realm, msg types.MsgIntentPacketRecv) {
	requireCanCall(0, cur, SelectorIntentPacketRecv)

	marketMaker := cur.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}

	first := msg.Packets[0]
	destinationChannelId := first.DestinationChannelId
	channel := store.getChannel(destinationChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	portId := store.getChannelOwner(destinationChannelId)
	intentApp, ok := store.getAppByPortId(portId).(app.IIntentApp)
	if !ok {
		panic(ErrIntentNotSupported)
	}

	c := store.clientForChannel(destinationChannelId)
	now := nowNanos()

	for i, marketMakerMsg := range msg.MarketMakerMessages {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		channel, skip := acceptRecvPacket(c, packet, destinationChannelId, now)
		if skip {
			continue
		}

		res := intentApp.OnIntentRecvPacket(cross(cur), packet, marketMaker, marketMakerMsg)
		if err := commitSyncAck(c, packet, res); err != nil {
			panic(err)
		}

		emitPacketRecvEvent(IntentPacketRecvEvent, packet, channel, connection, "market_maker_msg", marketMakerMsg)
	}
}

func PacketAcknowledgement(cur realm, msg types.MsgPacketAcknowledgement) {
	requireCanCall(0, cur, SelectorPacketAck)

	relayer := cur.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(ErrNotEnoughPackets)
	}

	first := msg.Packets[0]

	sourceChannelId := first.SourceChannelId

	channel := store.getChannel(sourceChannelId)
	connection := ensureConnectionOpen(channel.ConnectionId)

	batchHash := commitPacketsHash(msg.Packets)
	commitmentKey := types.BatchReceiptsPath(batchHash)
	commitmentValue := types.CommitAcks(msg.Acknowledgements)

	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, commitmentKey[:], commitmentValue[:])

	portId := store.getChannelOwner(sourceChannelId)
	c := store.clientForChannel(sourceChannelId)

	for i, ack := range msg.Acknowledgements {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		// Validate same channel before the commitment check so that a mixed-channel
		// batch is always rejected, not silently skipped.
		if packet.SourceChannelId != first.SourceChannelId {
			panic(ErrBatchSameChannelOnly)
		}
		if err := c.markPacketAcknowledged(packet); err != nil {
			panic(err)
		}

		store.getAppByPortId(portId).OnAcknowledgementPacket(cross(cur), packet, ack, relayer)

		emitPacketAckEvent(packet, channel, connection, ack)
	}
}

func PacketTimeout(cur realm, msg types.MsgPacketTimeout) {
	requireCanCall(0, cur, SelectorPacketTimeout)

	relayer := cur.Previous().Address()
	packet := msg.Packet

	channel := store.getChannel(packet.SourceChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	c := store.clientForChannel(packet.SourceChannelId)

	proofTimestamp, err := c.lightClient.GetTimestampAtHeight(msg.ProofHeight)
	if err != nil {
		panic(err)
	}
	if proofTimestamp == 0 {
		panic(ErrTimeoutProofTimestampNotFound)
	}

	commitmentKey := types.BatchReceiptsPath(commitPacketHash(packet))
	verifyNonMembershipWithActiveClient(c, types.NewHeight(msg.ProofHeight), msg.Proof, commitmentKey[:])

	if err := c.markPacketAcknowledged(packet); err != nil {
		panic(err)
	}
	if packet.TimeoutTimestamp == 0 {
		panic(ErrTimeoutMustBeSet)
	}
	if packet.TimeoutTimestamp > proofTimestamp {
		panic(ErrPacketTimeoutNotReached)
	}

	portId := store.getChannelOwner(packet.SourceChannelId)
	store.getAppByPortId(portId).OnTimeoutPacket(cross(cur), packet, relayer)

	emitPacketTimeoutEvent(packet, channel, connection)
}

func CommitMembershipProof(cur realm, msg types.MsgCommitMembershipProof) {
	requireCanCall(0, cur, SelectorCommitMembershipProof)

	verifyMembershipActive(msg.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, msg.Path, msg.Value)
	store.saveMembershipProof(msg.ClientId, msg.ProofHeight, msg.Path, types.Keccak(msg.Value))

	emitCommitMembershipProofEvent(msg)
}

func CommitNonMembershipProof(cur realm, msg types.MsgCommitNonMembershipProof) {
	requireCanCall(0, cur, SelectorCommitNonMembershipProof)

	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}
	verifyNonMembershipWithActiveClient(c, types.NewHeight(msg.ProofHeight), msg.Proof, msg.Path)
	store.saveNonMembershipProof(msg.ClientId, msg.ProofHeight, msg.Path, types.NON_MEMBERSHIP_COMMITMENT_VALUE)

	emitCommitNonMembershipProofEvent(msg)
}

func BatchSend(cur realm, msg types.MsgBatchSend) {
	requireCanCall(0, cur, SelectorBatchSend)

	if len(msg.Packets) < 2 {
		panic(ErrNotEnoughPackets)
	}
	first := msg.Packets[0]
	channelId := first.SourceChannelId
	batchHash := commitPacketsHash(msg.Packets)

	c := store.clientForChannel(channelId)
	for _, packet := range msg.Packets {
		if packet.SourceChannelId != channelId {
			panic(ErrBatchSameChannelOnly)
		}
		commitment, ok := c.getBatchPacketsAtPath(packetCommitmentPath(packet))
		if !ok {
			panic(ErrPacketCommitmentNotFound)
		}
		if commitment != types.COMMITMENT_MAGIC {
			panic(ErrPacketCommitmentNotFound)
		}

		packetHash := commitPacketsHash([]types.Packet{packet})
		emitBatchSendEvent(channelId, packetHash, batchHash)
	}

	c.saveBatchPackets(batchHash, types.COMMITMENT_MAGIC)
}

func BatchAcks(cur realm, msg types.MsgBatchAcks) {
	requireCanCall(0, cur, SelectorBatchAcks)

	if len(msg.Packets) < 2 {
		panic(ErrNotEnoughPackets)
	}

	first := msg.Packets[0]
	channelId := first.DestinationChannelId

	batchHash := commitPacketsHash(msg.Packets)

	c := store.clientForChannel(channelId)
	for i, ack := range msg.Acks {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		if packet.DestinationChannelId != channelId {
			panic(ErrBatchSameChannelOnly)
		}

		packetHash := commitPacketsHash([]types.Packet{packet})
		emitBatchAcksEvent(channelId, packetHash, batchHash)

		commitmentKey := packetAcknowledgementPath(packet)
		commitment, ok := c.getBatchReceiptsAtPath(commitmentKey)
		if !ok {
			panic(ErrPacketCommitmentNotFound)
		}

		if commitment == types.COMMITMENT_MAGIC {
			panic(ErrAcknowledgementEmpty)
		}
		if expected := types.CommitAcks([][]byte{ack}); commitment != expected {
			panic(ErrAcknowledgementMismatch)
		}
	}

	c.saveBatchReceipts(batchHash, types.CommitAcks(msg.Acks))
}

// WriteAcknowledgement commits an acknowledgement for a previously received
// packet. Async acknowledgement ownership is protocol-managed: core does not
// track pending async acknowledgement state.
func WriteAcknowledgement(cur realm, msg types.MsgWriteAcknowledgement) {
	if len(msg.Acknowledgement) == 0 {
		panic(ErrAcknowledgementEmpty)
	}

	channelId := msg.Packet.DestinationChannelId

	portId := store.getChannelOwner(channelId)
	if string(portId) != cur.Previous().PkgPath() {
		panic(ErrUnauthorizedAckWriter)
	}

	c := store.clientForChannel(channelId)
	commitment, ok := c.getBatchReceiptsAtPath(packetAcknowledgementPath(msg.Packet))
	if !ok {
		panic(ErrPacketReceiptNotFound)
	}
	if commitment != types.COMMITMENT_MAGIC {
		panic(ErrAcknowledgementAlreadyWritten)
	}

	c.commitAcknowledgement(msg.Packet, msg.Acknowledgement)

	emitWriteAckEvent(channelId, msg.Packet, msg.Acknowledgement)
}

// acceptRecvPacket validates recv-path invariants and records a packet
// receipt. Receipts serve as both replay protection and the source-side
// timeout signal.
func acceptRecvPacket(c *client, packet types.Packet, batchChannelId types.ChannelId, now uint64) (types.Channel, bool) {
	if packet.DestinationChannelId != batchChannelId {
		panic(ErrBatchSameChannelOnly)
	}
	channel := store.getChannel(packet.DestinationChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}

	// Do not execute packets that have already timed out on the source chain.
	if now >= uint64(packet.TimeoutTimestamp) {
		panic(ErrPacketTimeoutExpired)
	}

	// Ignore duplicate packets so batch retries remain idempotent.
	if c.hasPacketReceipt(packet) {
		return channel, true
	}

	c.setPacketReceipt(packet)
	return channel, false
}

// commitSyncAck records non-async recv results as Union receipt evidence.
// Sync success and failure results must carry a non-empty acknowledgement.
func commitSyncAck(c *client, packet types.Packet, res types.RecvPacketResult) error {
	switch res.Status {
	case types.PacketStatusAsync:
	case types.PacketStatusSuccess, types.PacketStatusFailure:
		if len(res.Acknowledgement) == 0 {
			return ErrSyncAckEmpty
		}
		c.commitAcknowledgement(packet, res.Acknowledgement)
		emitWriteAckEvent(packet.DestinationChannelId, packet, res.Acknowledgement)
	default:
		return ErrUnknownPacketStatus
	}
	return nil
}
