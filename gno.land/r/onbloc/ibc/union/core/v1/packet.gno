package impl

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// packet.gno: the packet lifecycle. SendPacket and WriteAcknowledgement are
// caller-authorized (port owner); the recv/ack/timeout/batch/commit-proof
// entrypoints keep their admin gate on the proxy. Apps are notified via cross(rlm).

// SendPacket commits a packet for the caller's port. Per the spec the timeout
// height is always zero; only the timeout timestamp is meaningful.
func (c *coreV1) SendPacket(_ int, rlm realm, sourceChannelId types.ChannelId, timeoutTimestamp types.Timestamp, data []byte) types.Packet {
	if timeoutTimestamp == 0 {
		panic(core.ErrTimeoutMustBeSet)
	}

	portId, ok := c.store.GetChannelOwner(sourceChannelId)
	if !ok {
		panic("channel " + sourceChannelId.String() + " not found")
	}
	if string(portId) != rlm.Previous().PkgPath() {
		panic(core.ErrUnauthorizedPacketSender)
	}

	channel, ok := c.store.GetChannel(sourceChannelId)
	if !ok {
		panic("channel " + sourceChannelId.String() + " not found")
	}
	if channel.State != types.ChannelStateOpen {
		panic(core.ErrInvalidChannelState)
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)

	packet := types.Packet{
		SourceChannelId:      sourceChannelId,
		DestinationChannelId: channel.CounterpartyChannelId,
		Data:                 data,
		TimeoutHeight:        0,
		TimeoutTimestamp:     timeoutTimestamp,
	}
	if c.store.HasPacketCommitment(packet) {
		panic(core.ErrPacketCommitmentAlreadyExists)
	}
	c.store.CommitPacket(0, rlm, packet)

	core.EmitPacketSend(packet, channel, connection)
	return packet
}

// PacketRecv proves a batch of packets committed on the counterparty and
// dispatches each to its app, recording receipts and sync acks.
func (c *coreV1) PacketRecv(_ int, rlm realm, msg types.MsgPacketRecv) {
	relayer := rlm.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(core.ErrNotEnoughPackets)
	}

	destinationChannelId := msg.Packets[0].DestinationChannelId
	channel, ok := c.store.GetChannel(destinationChannelId)
	if !ok {
		panic("channel " + destinationChannelId.String() + " not found")
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)

	proofKey := types.BatchPacketsPath(core.CommitPacketsHash(msg.Packets))
	magic := types.COMMITMENT_MAGIC
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, proofKey[:], magic[:])

	portId, _ := c.store.GetChannelOwner(destinationChannelId)
	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic("port " + string(portId) + " not found")
	}
	now := core.NowNanos()

	for i, relayerMsg := range msg.RelayerMsgs {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		ch, skip := c.acceptRecvPacket(0, rlm, packet, destinationChannelId, now)
		if skip {
			continue
		}

		res := a.OnRecvPacket(cross(rlm), packet, relayer, relayerMsg)
		if err := c.commitSyncAck(0, rlm, packet, res); err != nil {
			panic(err)
		}
		core.EmitPacketRecv(packet, ch, connection, relayerMsg)
	}
}

// IntentPacketRecv settles packets on the proofless market-maker fast path.
func (c *coreV1) IntentPacketRecv(_ int, rlm realm, msg types.MsgIntentPacketRecv) {
	marketMaker := rlm.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(core.ErrNotEnoughPackets)
	}

	destinationChannelId := msg.Packets[0].DestinationChannelId
	channel, ok := c.store.GetChannel(destinationChannelId)
	if !ok {
		panic("channel " + destinationChannelId.String() + " not found")
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)

	portId, _ := c.store.GetChannelOwner(destinationChannelId)
	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic("port " + string(portId) + " not found")
	}
	intentApp, ok := a.(app.IIntentApp)
	if !ok {
		panic(core.ErrIntentNotSupported)
	}
	now := core.NowNanos()

	for i, marketMakerMsg := range msg.MarketMakerMessages {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		ch, skip := c.acceptRecvPacket(0, rlm, packet, destinationChannelId, now)
		if skip {
			continue
		}

		res := intentApp.OnIntentRecvPacket(cross(rlm), packet, marketMaker, marketMakerMsg)
		if err := c.commitSyncAck(0, rlm, packet, res); err != nil {
			panic(err)
		}
		core.EmitIntentPacketRecv(packet, ch, connection, marketMakerMsg)
	}
}

// PacketAcknowledgement proves the counterparty's acks and notifies the app.
func (c *coreV1) PacketAcknowledgement(_ int, rlm realm, msg types.MsgPacketAcknowledgement) {
	relayer := rlm.Previous().Address()
	if len(msg.Packets) == 0 {
		panic(core.ErrNotEnoughPackets)
	}

	first := msg.Packets[0]
	sourceChannelId := first.SourceChannelId
	channel, ok := c.store.GetChannel(sourceChannelId)
	if !ok {
		panic("channel " + sourceChannelId.String() + " not found")
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)

	commitmentKey := types.BatchReceiptsPath(core.CommitPacketsHash(msg.Packets))
	commitmentValue := types.CommitAcks(msg.Acknowledgements)
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, commitmentKey[:], commitmentValue[:])

	portId, _ := c.store.GetChannelOwner(sourceChannelId)
	a, _ := c.store.GetAppByPortId(portId)

	for i, ack := range msg.Acknowledgements {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		if packet.SourceChannelId != first.SourceChannelId {
			panic(core.ErrBatchSameChannelOnly)
		}
		c.markPacketAcknowledged(0, rlm, packet)

		a.OnAcknowledgementPacket(cross(rlm), packet, ack, relayer)
		core.EmitPacketAck(packet, channel, connection, ack)
	}
}

// PacketTimeout proves the counterparty never received the packet and notifies
// the app to refund.
func (c *coreV1) PacketTimeout(_ int, rlm realm, msg types.MsgPacketTimeout) {
	relayer := rlm.Previous().Address()
	packet := msg.Packet

	channel, ok := c.store.GetChannel(packet.SourceChannelId)
	if !ok {
		panic("channel " + packet.SourceChannelId.String() + " not found")
	}
	if channel.State != types.ChannelStateOpen {
		panic(core.ErrInvalidChannelState)
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)

	lc, ok := c.store.GetLightClient(connection.ClientId)
	if !ok {
		panic("client " + connection.ClientId.String() + " not found")
	}
	proofTimestamp, err := lc.GetTimestampAtHeight(msg.ProofHeight)
	if err != nil {
		panic(err)
	}
	if proofTimestamp == 0 {
		panic(core.ErrTimeoutProofTimestampNotFound)
	}

	commitmentKey := types.BatchReceiptsPath(core.CommitPacketHash(packet))
	c.verifyNonMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, commitmentKey[:])

	c.markPacketAcknowledged(0, rlm, packet)
	if packet.TimeoutTimestamp == 0 {
		panic(core.ErrTimeoutMustBeSet)
	}
	if uint64(packet.TimeoutTimestamp) > uint64(proofTimestamp) {
		panic(core.ErrPacketTimeoutNotReached)
	}

	portId, _ := c.store.GetChannelOwner(packet.SourceChannelId)
	a, _ := c.store.GetAppByPortId(portId)
	a.OnTimeoutPacket(cross(rlm), packet, relayer)

	core.EmitPacketTimeout(packet, channel, connection)
}

// markPacketAcknowledged is the source-side acknowledge/timeout state machine.
// It verifies the packet's commitment exists and is not already acknowledged,
// then flips it through the store's pure SetPacketAcknowledged primitive. Acks
// and timeouts share it: both retire a sent packet exactly once.
func (c *coreV1) markPacketAcknowledged(_ int, rlm realm, packet types.Packet) {
	commitment, ok := c.store.PacketCommitment(packet.SourceChannelId, packet)
	if !ok {
		panic(core.ErrPacketCommitmentNotFound)
	}
	if commitment == types.COMMITMENT_MAGIC_ACK {
		panic(core.ErrPacketAlreadyAcknowledged)
	}
	if commitment != types.COMMITMENT_MAGIC {
		panic(core.ErrPacketCommitmentNotFound)
	}
	c.store.SetPacketAcknowledged(0, rlm, packet)
}

// CommitMembershipProof verifies and records a membership proof for later reuse.
func (c *coreV1) CommitMembershipProof(_ int, rlm realm, msg types.MsgCommitMembershipProof) {
	c.verifyMembership(msg.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, msg.Path, msg.Value)
	c.store.SaveMembershipProof(0, rlm, msg.ClientId, msg.ProofHeight, msg.Path, types.Keccak(msg.Value))
	core.EmitCommitMembershipProof(msg)
}

// CommitNonMembershipProof verifies and records a non-membership proof.
func (c *coreV1) CommitNonMembershipProof(_ int, rlm realm, msg types.MsgCommitNonMembershipProof) {
	if !c.store.ClientExists(msg.ClientId) {
		panic("client " + msg.ClientId.String() + " not found")
	}
	c.verifyNonMembership(msg.ClientId, types.NewHeight(msg.ProofHeight), msg.Proof, msg.Path)
	c.store.SaveNonMembershipProof(0, rlm, msg.ClientId, msg.ProofHeight, msg.Path, types.NON_MEMBERSHIP_COMMITMENT_VALUE)
	core.EmitCommitNonMembershipProof(msg)
}

// BatchSend aggregates several already-committed packets into a single batch
// commitment.
func (c *coreV1) BatchSend(_ int, rlm realm, msg types.MsgBatchSend) {
	if len(msg.Packets) < 2 {
		panic(core.ErrNotEnoughPackets)
	}
	channelId := msg.Packets[0].SourceChannelId
	batchHash := core.CommitPacketsHash(msg.Packets)

	for _, packet := range msg.Packets {
		if packet.SourceChannelId != channelId {
			panic(core.ErrBatchSameChannelOnly)
		}
		commitment, ok := c.store.PacketCommitment(channelId, packet)
		if !ok || commitment != types.COMMITMENT_MAGIC {
			panic(core.ErrPacketCommitmentNotFound)
		}

		packetHash := core.CommitPacketsHash([]types.Packet{packet})
		core.EmitBatchSend(channelId, packetHash, batchHash)
	}

	c.store.SaveBatchPackets(0, rlm, channelId, batchHash, types.COMMITMENT_MAGIC)
}

// BatchAcks aggregates the acks of several received packets into a batch receipt.
func (c *coreV1) BatchAcks(_ int, rlm realm, msg types.MsgBatchAcks) {
	if len(msg.Packets) < 2 {
		panic(core.ErrNotEnoughPackets)
	}
	channelId := msg.Packets[0].DestinationChannelId
	batchHash := core.CommitPacketsHash(msg.Packets)

	for i, ack := range msg.Acks {
		if i >= len(msg.Packets) {
			break
		}
		packet := msg.Packets[i]
		if packet.DestinationChannelId != channelId {
			panic(core.ErrBatchSameChannelOnly)
		}

		packetHash := core.CommitPacketsHash([]types.Packet{packet})
		core.EmitBatchAcks(channelId, packetHash, batchHash)

		commitment, ok := c.store.AcknowledgementReceipt(channelId, packet)
		if !ok {
			panic(core.ErrPacketCommitmentNotFound)
		}
		if commitment == types.COMMITMENT_MAGIC {
			panic(core.ErrAcknowledgementEmpty)
		}
		if expected := types.CommitAcks([][]byte{ack}); commitment != expected {
			panic(core.ErrAcknowledgementMismatch)
		}
	}

	c.store.SaveBatchReceipts(0, rlm, channelId, batchHash, types.CommitAcks(msg.Acks))
}

// WriteAcknowledgement commits a (previously deferred) acknowledgement for a
// received packet. Only the channel's port owner may write it.
func (c *coreV1) WriteAcknowledgement(_ int, rlm realm, msg types.MsgWriteAcknowledgement) {
	if len(msg.Acknowledgement) == 0 {
		panic(core.ErrAcknowledgementEmpty)
	}

	channelId := msg.Packet.DestinationChannelId
	portId, ok := c.store.GetChannelOwner(channelId)
	if !ok {
		panic("channel " + channelId.String() + " not found")
	}
	if string(portId) != rlm.Previous().PkgPath() {
		panic(core.ErrUnauthorizedAckWriter)
	}

	commitment, ok := c.store.AcknowledgementReceipt(channelId, msg.Packet)
	if !ok {
		panic(core.ErrPacketReceiptNotFound)
	}
	if commitment != types.COMMITMENT_MAGIC {
		panic(core.ErrAcknowledgementAlreadyWritten)
	}

	c.store.CommitAcknowledgement(0, rlm, msg.Packet, msg.Acknowledgement)
	core.EmitWriteAck(channelId, msg.Packet, msg.Acknowledgement)
}

// --- shared recv helpers ---

// acceptRecvPacket validates recv-path invariants and records a packet receipt,
// returning skip=true for an already-received (duplicate) packet.
func (c *coreV1) acceptRecvPacket(_ int, rlm realm, packet types.Packet, batchChannelId types.ChannelId, now uint64) (types.Channel, bool) {
	if packet.DestinationChannelId != batchChannelId {
		panic(core.ErrBatchSameChannelOnly)
	}
	channel, ok := c.store.GetChannel(packet.DestinationChannelId)
	if !ok {
		panic("channel " + packet.DestinationChannelId.String() + " not found")
	}
	if channel.State != types.ChannelStateOpen {
		panic(core.ErrInvalidChannelState)
	}
	if now >= uint64(packet.TimeoutTimestamp) {
		panic(core.ErrPacketTimeoutExpired)
	}
	if c.store.HasPacketReceipt(packet) {
		return channel, true
	}
	c.store.SetPacketReceipt(0, rlm, packet)
	return channel, false
}

// commitSyncAck records a synchronous recv result as receipt evidence. Sync
// success/failure must carry a non-empty acknowledgement; async is deferred.
func (c *coreV1) commitSyncAck(_ int, rlm realm, packet types.Packet, res types.RecvPacketResult) error {
	switch res.Status {
	case types.PacketStatusAsync:
		return nil
	case types.PacketStatusSuccess, types.PacketStatusFailure:
		if len(res.Acknowledgement) == 0 {
			return core.ErrSyncAckEmpty
		}
		c.store.CommitAcknowledgement(0, rlm, packet, res.Acknowledgement)
		core.EmitWriteAck(packet.DestinationChannelId, packet, res.Acknowledgement)
		return nil
	default:
		return core.ErrUnknownPacketStatus
	}
}

// verifyNonMembership checks a non-membership proof against an active light client.
func (c *coreV1) verifyNonMembership(clientId types.ClientId, height types.Height, proof, key []byte) {
	lc, ok := c.store.GetLightClient(clientId)
	if !ok {
		panic("client " + clientId.String() + " not found")
	}
	if lc.Status() != lightclient.Active {
		panic(core.ErrClientNotActive)
	}
	if err := lc.VerifyNonMembership(height.RevisionHeight, key, proof); err != nil {
		panic(err)
	}
}
