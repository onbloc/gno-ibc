package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

// GetStatus returns a client's status (union GetStatus).
func GetStatus(clientId types.ClientId) types.Status {
	return mustGetImpl().GetStatus(clientId)
}

// GetClientImpl returns the impl identifier for a client (best-effort: type).
func GetClientImpl(clientId types.ClientId) (string, bool) {
	return mustGetImpl().GetClientImpl(clientId)
}

// GetRegisteredClientType reports whether a client type is registered (best-effort).
func GetRegisteredClientType(clientType types.ClientType) bool {
	return mustGetImpl().GetRegisteredClientType(clientType)
}

// GetClientState returns the raw mirrored client state bytes (union GetClientState).
func GetClientState(clientId types.ClientId) ([]byte, bool) {
	return mustGetImpl().GetClientStateBytes(clientId)
}

// GetConsensusState returns the raw consensus state bytes at a height
// (union GetConsensusState).
func GetConsensusState(clientId types.ClientId, height types.Height) ([]byte, bool) {
	return mustGetImpl().GetConsensusStateBytes(clientId, height)
}

// GetLatestHeight returns a client's latest height (union GetLatestHeight).
func GetLatestHeight(clientId types.ClientId) (uint64, bool) {
	return mustGetImpl().GetLatestHeight(clientId)
}

// GetTimestampAtHeight returns the consensus timestamp at a height
// (union GetTimestampAtHeight).
func GetTimestampAtHeight(clientId types.ClientId, height uint64) (types.Timestamp, bool) {
	return mustGetImpl().GetTimestampAtHeight(clientId, height)
}

// GetConnection returns the typed connection record (union GetConnection).
func GetConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	return mustGetImpl().GetConnectionTyped(connectionId)
}

// GetChannels returns the channel ids owned by an app contract (best-effort: nil).
func GetChannels(contract string) []types.ChannelId {
	return mustGetImpl().GetChannels(contract)
}

// GetBatchPackets returns the batch packet commitment for a batch hash
// (union GetBatchPackets; gno additionally requires the channel id).
func GetBatchPackets(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return mustGetImpl().GetBatchPacketsCommitment(channelId, batchHash)
}

// GetBatchReceipts returns the batch receipt commitment for a batch hash
// (union GetBatchReceipts; gno additionally requires the channel id).
func GetBatchReceipts(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return mustGetImpl().GetBatchReceiptsCommitment(channelId, batchHash)
}
