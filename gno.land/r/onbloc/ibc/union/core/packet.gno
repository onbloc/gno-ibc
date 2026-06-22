package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

func NewPacket(sourceChannelId, destinationChannelId types.ChannelId, data []byte, timeoutTimestamp types.Timestamp) types.Packet {
	return types.Packet{SourceChannelId: sourceChannelId, DestinationChannelId: destinationChannelId, Data: data, TimeoutHeight: 0, TimeoutTimestamp: timeoutTimestamp}
}

func NewRecvPacketResult(status types.PacketStatus, acknowledgement []byte) types.RecvPacketResult {
	return types.RecvPacketResult{Status: status, Acknowledgement: acknowledgement}
}

// QueryBatchPackets returns the batch commitment value stored at
// types.BatchPacketsPath(batchHash). Commitments are keyed by their global path,
// so channelId is accepted for API compatibility but no longer routes the read.
func QueryBatchPackets(channelId types.ChannelId, batchHash types.H256) string {
	v, found := store.getCommitment(types.BatchPacketsPath(batchHash))
	if !found {
		return ""
	}
	return h256String(v)
}

// QueryBatchReceipts returns the batch receipt value stored at
// types.BatchReceiptsPath(batchHash).
func QueryBatchReceipts(channelId types.ChannelId, batchHash types.H256) string {
	v, found := store.getCommitment(types.BatchReceiptsPath(batchHash))
	if !found {
		return ""
	}
	return h256String(v)
}

// QueryCommitmentAtPath reads the commitment stored at an already-derived path.
func QueryCommitmentAtPath(channelId types.ChannelId, path types.H256) string {
	v, found := store.getCommitment(path)
	if !found {
		return ""
	}
	return h256String(v)
}

// QueryReceiptAtPath reads the receipt commitment stored at an already-derived path.
func QueryReceiptAtPath(channelId types.ChannelId, path types.H256) string {
	v, found := store.getCommitment(path)
	if !found {
		return ""
	}
	return h256String(v)
}

func GetCommittedMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte) string {
	v, found := store.getMembershipProof(clientId, proofHeight, path)
	if !found {
		return ""
	}
	return h256String(v)
}

func GetCommittedNonMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte) bool {
	return store.hasNonMembershipProof(clientId, proofHeight, path)
}
