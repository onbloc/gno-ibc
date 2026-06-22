package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

// GetStatus returns a client's status (union GetStatus).
func GetStatus(clientId types.ClientId) types.Status {
	return getImpl().GetStatus(clientId)
}

// GetClientImpl returns the impl identifier for a client (best-effort: type).
func GetClientImpl(clientId types.ClientId) (string, bool) {
	return getImpl().GetClientImpl(clientId)
}

// GetRegisteredClientType reports whether a client type is registered (best-effort).
func GetRegisteredClientType(clientType types.ClientType) bool {
	return getImpl().GetRegisteredClientType(clientType)
}

// GetClientState returns the raw mirrored client state bytes (union GetClientState).
func GetClientState(clientId types.ClientId) ([]byte, bool) {
	return getImpl().GetClientStateBytes(clientId)
}

// GetConsensusState returns the raw consensus state bytes at a height
// (union GetConsensusState).
func GetConsensusState(clientId types.ClientId, height types.Height) ([]byte, bool) {
	return getImpl().GetConsensusStateBytes(clientId, height)
}

// GetLatestHeight returns a client's latest height (union GetLatestHeight).
func GetLatestHeight(clientId types.ClientId) (uint64, bool) {
	return getImpl().GetLatestHeight(clientId)
}

// GetTimestampAtHeight returns the consensus timestamp at a height
// (union GetTimestampAtHeight).
func GetTimestampAtHeight(clientId types.ClientId, height uint64) (types.Timestamp, bool) {
	return getImpl().GetTimestampAtHeight(clientId, height)
}

// GetConnection returns the typed connection record (union GetConnection).
func GetConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	return getImpl().GetConnectionTyped(connectionId)
}

// GetChannels returns the channel ids owned by an app contract (best-effort: nil).
func GetChannels(contract string) []types.ChannelId {
	return getImpl().GetChannels(contract)
}

// GetBatchPackets returns the batch packet commitment for a batch hash
// (union GetBatchPackets; gno additionally requires the channel id).
func GetBatchPackets(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return getImpl().GetBatchPacketsCommitment(channelId, batchHash)
}

// GetBatchReceipts returns the batch receipt commitment for a batch hash
// (union GetBatchReceipts; gno additionally requires the channel id).
func GetBatchReceipts(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return getImpl().GetBatchReceiptsCommitment(channelId, batchHash)
}

func getImpl() ICore {
	if impl == nil {
		panic("core: implementation not installed")
	}

	return impl
}
