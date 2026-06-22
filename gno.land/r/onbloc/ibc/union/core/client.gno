package core

import (
	"chain/runtime"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

func NewConsensusStateUpdate(height types.Height, consensusStateBytes, clientStateBytes []byte) types.ConsensusStateUpdate {
	return types.ConsensusStateUpdate{Height: height, ConsensusStateBytes: consensusStateBytes, ClientStateBytes: clientStateBytes}
}

func RegisterClient(cur realm, clientType types.ClientType, lc lightclient.Interface) {
	if lc == nil {
		panic("caller not authorized to register client: unauthorized")
	}
	store.registerClient(clientType, lc)
	emitRegisterClientEvent(clientType)
}

func HasClient(clientType types.ClientType) bool {
	return store.hasRegisteredClient(clientType)
}

// CreateClient assigns a client id for a registered light client type, stores
// the submitted state bytes, then lets the light client verify creation against
// that freshly stored state.
func CreateClient(cur realm, msg types.MsgCreateClient) types.ClientId {
	creator := cur.Previous().Address()
	lc, ok := store.registeredClient(msg.ClientType)
	if !ok {
		panic("client type not found")
	}
	relayer := creator
	if msg.Relayer != "" {
		relayer = address(msg.Relayer)
	}

	clientId := store.nextClientId()
	c := store.addClient(clientId, msg.ClientType, creator, lc)
	initClient(creator, msg.ClientStateBytes, msg.ConsensusStateBytes, relayer, clientId)

	emitCreateClientEvent(c.id, msg.ClientType, lc.GetCounterpartyChainID())

	return c.id
}

func initClient(caller address, clientStateBytes, consensusStateBytes []byte, relayer address, clientId types.ClientId) types.Height {
	c := store.getClient(clientId)
	if c == nil {
		panic("client " + clientId.String() + " not found")
	}

	c.saveClientState(clientStateBytes)
	height := types.NewHeight(c.lightClient.GetLatestHeight())
	c.saveConsensusState(height, consensusStateBytes)

	result, err := c.lightClient.VerifyCreation(caller, relayer)
	if err != nil {
		panic("create client: " + err.Error())
	}

	if len(result.ClientStateBytes) != 0 {
		c.saveClientState(result.ClientStateBytes)
	}
	for k, v := range result.StorageWrites {
		c.saveClientStore(k, v)
	}

	return height
}

// UpdateClient verifies a client message against the light client object, which
// updates its own state, and mirrors the resulting state bytes for queries and
// counterparty proofs.
func UpdateClient(cur realm, msg types.MsgUpdateClient) types.Height {
	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}

	requireActiveClient(c)

	caller := cur.Previous().Address()
	relayer := caller
	if msg.Relayer != "" {
		relayer = address(msg.Relayer)
	}

	update, err := c.lightClient.VerifyHeader(caller, msg.ClientMessage, relayer)
	if err != nil {
		panic("update client: " + err.Error())
	}

	height := types.NewHeight(update.Height)
	if len(update.ClientStateBytes) != 0 {
		c.saveClientState(update.ClientStateBytes)
	}

	if len(update.ConsensusStateBytes) != 0 {
		c.saveConsensusState(height, update.ConsensusStateBytes)
	}
	for k, v := range update.StorageWrites {
		c.saveClientStore(k, v)
	}

	emitUpdateClientEvent(msg.ClientId, height)

	return height
}

// ForceUpdateClient re-initializes a client from submitted state bytes,
// bypassing header proof verification.
//
// It is restricted to the admin and recovers expired or otherwise unrecoverable
// clients. The registered light client type for the existing client is reused.
func ForceUpdateClient(cur realm, msg types.MsgForceUpdateClient) types.Height {
	requireAdmin(cur, "ForceUpdateClient")

	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}

	runtime.AssertOriginCall()
	caller := cur.Previous().Address()
	height := initClient(caller, msg.ClientStateBytes, msg.ConsensusStateBytes, caller, msg.ClientId)

	emitForceUpdateClientEvent(msg.ClientId, height)

	return height
}

// VerifyClientMembership verifies a membership proof against a registered light client.
//
// It does not commit the verified value into this realm's state.
func VerifyClientMembership(_ realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte) {
	verifyMembershipActive(clientId, proofHeight, proof, path, value)
}

// statusToTypes maps the light client object's status (a string) to the core
// status enum.
func statusToTypes(s lightclient.Status) types.Status {
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

func requireActiveClient(c *client) {
	if statusToTypes(c.lightClient.Status()) != types.StatusActive {
		panic(ErrClientNotActive)
	}
}

func verifyMembershipActive(clientId types.ClientId, height types.Height, proof, key, value []byte) {
	c := store.getClient(clientId)
	if c == nil {
		panic("client " + clientId.String() + " not found")
	}

	requireActiveClient(c)

	if err := c.lightClient.VerifyMembership(height.RevisionHeight, key, proof, value); err != nil {
		panic(err)
	}
}

func verifyNonMembershipWithActiveClient(c *client, height types.Height, proof, key []byte) {
	requireActiveClient(c)

	if err := c.lightClient.VerifyNonMembership(height.RevisionHeight, key, proof); err != nil {
		panic(err)
	}
}

// GetLightClient returns the stored light client object for clientId.
func GetLightClient(clientId types.ClientId) (lightclient.Interface, bool) {
	return store.lightClientOf(clientId)
}

// GetClientState returns the stored client state bytes.
func GetClientState(clientId types.ClientId) []byte {
	c := store.getClient(clientId)
	if c == nil {
		return nil
	}

	return cloneBytes(c.clientState)
}

// GetConsensusState returns the consensus state bytes at height.
func GetConsensusState(clientId types.ClientId, height uint64) []byte {
	c := store.getClient(clientId)
	if c == nil {
		return nil
	}

	bz, found := c.getConsensusState(types.NewHeight(height))
	if !found {
		return nil
	}

	return cloneBytes(bz)
}

func GetLatestHeight(clientId types.ClientId) uint64 {
	c := store.getClient(clientId)
	if c == nil {
		return 0
	}

	return c.lightClient.GetLatestHeight()
}

func GetTimestampAtHeight(clientId types.ClientId, height uint64) types.Timestamp {
	c := store.getClient(clientId)
	if c == nil {
		return 0
	}

	timestamp, err := c.lightClient.GetTimestampAtHeight(height)
	if err != nil {
		return 0
	}

	return timestamp
}

// GetStatus returns the current status reported by a registered light client.
func GetStatus(clientId types.ClientId) types.Status {
	c := store.getClient(clientId)
	if c == nil {
		return types.StatusUnknown
	}

	return statusToTypes(c.lightClient.Status())
}

// GetClientType returns the registered client type for clientId.
func GetClientType(clientId types.ClientId) string {
	c := store.getClient(clientId)
	if c == nil {
		return ""
	}

	return c.typ.String()
}
