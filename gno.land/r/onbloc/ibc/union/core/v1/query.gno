package impl

import (
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// query.gno implements the read-only IQuery surface. Results read the injected
// store / light client; missing state is signalled by the bool return.

// GetStatus returns the client's status, or StatusUnknown when missing.
func (c *coreV1) GetStatus(clientId types.ClientId) types.Status {
	lc, ok := c.store.GetLightClient(clientId)
	if !ok {
		return types.StatusUnknown
	}
	return mapStatus(lc.Status())
}

// GetClientType returns the registered client type for a client.
func (c *coreV1) GetClientType(clientId types.ClientId) (types.ClientType, bool) {
	return c.store.ClientType(clientId)
}

// GetClientImpl is best-effort: gno has no client_type->impl address mapping, so
// it returns the registered client type as the impl identifier.
func (c *coreV1) GetClientImpl(clientId types.ClientId) (string, bool) {
	typ, ok := c.store.ClientType(clientId)
	if !ok {
		return "", false
	}
	return string(typ), true
}

// GetRegisteredClientType is best-effort: gno registers light client objects per
// client id rather than a global client-type registry, so there is no
// registered-type set to query; it always reports false.
func (c *coreV1) GetRegisteredClientType(clientType types.ClientType) bool {
	return false
}

// GetClientStateBytes returns the mirrored client state bytes.
func (c *coreV1) GetClientStateBytes(clientId types.ClientId) ([]byte, bool) {
	return c.store.ClientStateBytes(clientId)
}

// GetConsensusStateBytes returns the consensus state bytes at a height.
func (c *coreV1) GetConsensusStateBytes(clientId types.ClientId, height types.Height) ([]byte, bool) {
	return c.store.ConsensusStateBytes(clientId, height)
}

// GetLatestHeight returns the light client's latest height.
func (c *coreV1) GetLatestHeight(clientId types.ClientId) (uint64, bool) {
	lc, ok := c.store.GetLightClient(clientId)
	if !ok {
		return 0, false
	}
	return lc.GetLatestHeight(), true
}

// GetTimestampAtHeight returns the consensus timestamp recorded at a height.
func (c *coreV1) GetTimestampAtHeight(clientId types.ClientId, height uint64) (types.Timestamp, bool) {
	lc, ok := c.store.GetLightClient(clientId)
	if !ok {
		return 0, false
	}
	ts, err := lc.GetTimestampAtHeight(height)
	if err != nil {
		return 0, false
	}
	return ts, true
}

// GetConnectionTyped returns the typed connection record.
func (c *coreV1) GetConnectionTyped(connectionId types.ConnectionId) (types.Connection, bool) {
	return c.store.GetConnection(connectionId)
}

// GetChannelTyped returns the typed channel record.
func (c *coreV1) GetChannelTyped(channelId types.ChannelId) (types.Channel, bool) {
	return c.store.GetChannel(channelId)
}

// GetChannels is best-effort: gno tracks channel->port ownership but not a
// per-app channel set, so the app->channels enumeration is unavailable.
func (c *coreV1) GetChannels(contract string) []types.ChannelId {
	return nil
}

// GetBatchPacketsCommitment returns the batch packet commitment for a batch hash.
func (c *coreV1) GetBatchPacketsCommitment(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return c.store.BatchPacketsAt(channelId, batchHash)
}

// GetBatchReceiptsCommitment returns the batch receipt commitment for a batch hash.
func (c *coreV1) GetBatchReceiptsCommitment(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return c.store.BatchReceiptsAt(channelId, batchHash)
}

// mapStatus maps a light client status to the core status enum.
func mapStatus(s lightclient.Status) types.Status {
	switch s {
	case lightclient.Active:
		return types.StatusActive
	case lightclient.Expired:
		return types.StatusExpired
	case lightclient.Frozen:
		return types.StatusFrozen
	default:
		return types.StatusUnknown
	}
}
