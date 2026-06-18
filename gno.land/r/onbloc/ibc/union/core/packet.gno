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

// GetBatchPackets returns the batch packet commitment for batchHash from the
// global commitment mirror.
func GetBatchPackets(batchHash types.H256) string {
	v, found := store.commitments[types.BatchPacketsPath(batchHash)]
	if !found {
		return ""
	}
	return h256String(v)
}

// QueryBatchPackets returns the batch commitment value stored at
// types.BatchPacketsPath(batchHash) for the client owning channelId.
func QueryBatchPackets(channelId types.ChannelId, batchHash types.H256) string {
	entry, ok := store.getChannelEntry(channelId)
	if !ok {
		return ""
	}
	c := store.getClient(entry.clientId)
	if c == nil {
		return ""
	}
	v, found := c.getBatchPacketsAtPath(types.BatchPacketsPath(batchHash))
	if !found {
		return ""
	}
	return h256String(v)
}

// GetBatchReceipts returns the batch receipt commitment for batchHash from the
// global commitment mirror.
func GetBatchReceipts(batchHash types.H256) string {
	v, found := store.commitments[types.BatchReceiptsPath(batchHash)]
	if !found {
		return ""
	}
	return h256String(v)
}

// QueryBatchReceipts returns the batch receipt value stored at
// types.BatchReceiptsPath(batchHash) for the client owning channelId.
func QueryBatchReceipts(channelId types.ChannelId, batchHash types.H256) string {
	entry, ok := store.getChannelEntry(channelId)
	if !ok {
		return ""
	}
	c := store.getClient(entry.clientId)
	if c == nil {
		return ""
	}
	v, found := c.getBatchReceiptsAtPath(types.BatchReceiptsPath(batchHash))
	if !found {
		return ""
	}
	return h256String(v)
}

// QueryCommitmentAtPath reads the client's batchPackets map by an
// already-derived commitment path for channelId's owning client.
func QueryCommitmentAtPath(channelId types.ChannelId, path types.H256) string {
	entry, ok := store.getChannelEntry(channelId)
	if !ok {
		return ""
	}
	c := store.getClient(entry.clientId)
	if c == nil {
		return ""
	}
	v, found := c.getBatchPacketsAtPath(path)
	if !found {
		return ""
	}
	return h256String(v)
}

// QueryReceiptAtPath reads the client's batchReceipts map by an
// already-derived commitment path for channelId's owning client.
func QueryReceiptAtPath(channelId types.ChannelId, path types.H256) string {
	entry, ok := store.getChannelEntry(channelId)
	if !ok {
		return ""
	}
	c := store.getClient(entry.clientId)
	if c == nil {
		return ""
	}
	v, found := c.getBatchReceiptsAtPath(path)
	if !found {
		return ""
	}
	return h256String(v)
}
