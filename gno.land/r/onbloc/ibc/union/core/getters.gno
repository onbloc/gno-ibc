package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

// getters.gno is the union-aligned read-only query surface. Each getter delegates
// to the installed impl's IQuery; missing state is signalled by the bool return
// rather than a panic. The typed GetChannel / GetClientType / GetClientStatus and
// the ABI-hex Query* helpers remain on their own files.
//
// Best-effort adaptations (no direct gno equivalent):
//   - GetClientImpl: union returns the impl contract address; gno has no
//     client_type->impl mapping, so it returns the registered client type string.
//   - GetRegisteredClientType: gno has no global client-type registry (light
//     client objects are registered per client id), so it reports false.
//   - GetChannels: gno tracks channel->port ownership but not a per-app channel
//     set, so the app->channels enumeration is unavailable (returns nil).

func requireQuery() IQuery {
	if impl == nil {
		panic("core: implementation not installed")
	}
	return impl
}

// GetStatus returns a client's status (union GetStatus).
func GetStatus(clientId types.ClientId) types.Status {
	return requireQuery().GetStatus(clientId)
}

// GetClientImpl returns the impl identifier for a client (best-effort: type).
func GetClientImpl(clientId types.ClientId) (string, bool) {
	return requireQuery().GetClientImpl(clientId)
}

// GetRegisteredClientType reports whether a client type is registered (best-effort).
func GetRegisteredClientType(clientType types.ClientType) bool {
	return requireQuery().GetRegisteredClientType(clientType)
}

// GetClientState returns the raw mirrored client state bytes (union GetClientState).
func GetClientState(clientId types.ClientId) ([]byte, bool) {
	return requireQuery().GetClientStateBytes(clientId)
}

// GetConsensusState returns the raw consensus state bytes at a height
// (union GetConsensusState).
func GetConsensusState(clientId types.ClientId, height types.Height) ([]byte, bool) {
	return requireQuery().GetConsensusStateBytes(clientId, height)
}

// GetLatestHeight returns a client's latest height (union GetLatestHeight).
func GetLatestHeight(clientId types.ClientId) (uint64, bool) {
	return requireQuery().GetLatestHeight(clientId)
}

// GetTimestampAtHeight returns the consensus timestamp at a height
// (union GetTimestampAtHeight).
func GetTimestampAtHeight(clientId types.ClientId, height uint64) (types.Timestamp, bool) {
	return requireQuery().GetTimestampAtHeight(clientId, height)
}

// GetConnection returns the typed connection record (union GetConnection).
func GetConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	return requireQuery().GetConnectionTyped(connectionId)
}

// GetChannels returns the channel ids owned by an app contract (best-effort: nil).
func GetChannels(contract string) []types.ChannelId {
	return requireQuery().GetChannels(contract)
}

// GetBatchPackets returns the batch packet commitment for a batch hash
// (union GetBatchPackets; gno additionally requires the channel id).
func GetBatchPackets(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return requireQuery().GetBatchPacketsCommitment(channelId, batchHash)
}

// GetBatchReceipts returns the batch receipt commitment for a batch hash
// (union GetBatchReceipts; gno additionally requires the channel id).
func GetBatchReceipts(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return requireQuery().GetBatchReceiptsCommitment(channelId, batchHash)
}
