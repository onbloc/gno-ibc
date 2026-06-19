package impl

import (
	"gno.land/p/onbloc/ibc/union/types"
)

// packet.gno: packet lifecycle (send/recv/ack/timeout, batches, proof commits).
// Pending migration from the core proxy — stubbed so coreV1 satisfies core.ICore.

func (c *coreV1) SendPacket(_ int, rlm realm, sourceChannelId types.ChannelId, timeoutTimestamp types.Timestamp, data []byte) types.Packet {
	panic(errNotMigrated)
}

func (c *coreV1) PacketRecv(_ int, rlm realm, msg types.MsgPacketRecv) {
	panic(errNotMigrated)
}

func (c *coreV1) IntentPacketRecv(_ int, rlm realm, msg types.MsgIntentPacketRecv) {
	panic(errNotMigrated)
}

func (c *coreV1) PacketAcknowledgement(_ int, rlm realm, msg types.MsgPacketAcknowledgement) {
	panic(errNotMigrated)
}

func (c *coreV1) PacketTimeout(_ int, rlm realm, msg types.MsgPacketTimeout) {
	panic(errNotMigrated)
}

func (c *coreV1) CommitMembershipProof(_ int, rlm realm, msg types.MsgCommitMembershipProof) {
	panic(errNotMigrated)
}

func (c *coreV1) CommitNonMembershipProof(_ int, rlm realm, msg types.MsgCommitNonMembershipProof) {
	panic(errNotMigrated)
}

func (c *coreV1) BatchSend(_ int, rlm realm, msg types.MsgBatchSend) {
	panic(errNotMigrated)
}

func (c *coreV1) BatchAcks(_ int, rlm realm, msg types.MsgBatchAcks) {
	panic(errNotMigrated)
}

func (c *coreV1) WriteAcknowledgement(_ int, rlm realm, msg types.MsgWriteAcknowledgement) {
	panic(errNotMigrated)
}
