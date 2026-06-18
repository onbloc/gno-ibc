package core

import (
	"chain"
	"chain/runtime"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

func NewConsensusStateUpdate(height types.Height, consensusStateBytes, clientStateBytes []byte) types.ConsensusStateUpdate {
	return types.ConsensusStateUpdate{Height: height, ConsensusStateBytes: consensusStateBytes, ClientStateBytes: clientStateBytes}
}

// CreateClient stores a light client object built by the caller (an
// app/bootstrap realm) and assigns it an id. The object owns its own client and
// consensus state. This mirrors aib's model of handing core an already-built
// light client instead of core decoding bytes itself.
func CreateClient(cur realm, clientType types.ClientType, lc lightclient.Interface) types.ClientId {
	creator := cur.Previous().Address()
	c := store.addClient(clientType, creator, lc)

	if _, err := lc.VerifyCreation(creator, creator); err != nil {
		panic("create client: " + err.Error())
	}

	chain.Emit(CreateClientEvent,
		"client_id", c.id.String(),
		"client_type", clientType.String(),
	)

	return c.id
}

// UpdateClient verifies a client message against the light client object, which
// updates its own state, and mirrors the resulting state bytes for queries and
// counterparty proofs.
func UpdateClient(cur realm, msg types.MsgUpdateClient) types.Height {
	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}

	caller := cur.Previous().Address()

	update, err := c.lightClient.VerifyHeader(caller, msg.ClientMessage, caller)
	if err != nil {
		panic("update client: " + err.Error())
	}

	height := types.NewHeight(update.Height)
	if len(update.ClientStateBytes) != 0 {
		c.saveState(update.ClientStateBytes)
	}

	if len(update.ConsensusStateBytes) != 0 {
		c.saveConsensusState(height, update.ConsensusStateBytes)
	}

	chain.Emit(UpdateClientEvent,
		"client_type", c.typ.String(),
		"client_id", msg.ClientId.String(),
		"height", height.String(),
	)

	return height
}

// ForceUpdateClient replaces a client's object with a new one built by the
// caller, bypassing proof verification.
//
// It is restricted to the admin and recovers expired or otherwise unrecoverable
// clients. Replacing the object with one the caller constructed from fresh state
// IS the recovery: the new object owns the new state.
func ForceUpdateClient(cur realm, clientId types.ClientId, lc lightclient.Interface) types.Height {
	requireAdmin(cur, "ForceUpdateClient")

	c := store.getClient(clientId)
	if c == nil {
		panic("client " + clientId.String() + " not found")
	}

	runtime.AssertOriginCall()

	c.lightClient = lc
	height := types.NewHeight(lc.GetLatestHeight())

	chain.Emit(UpdateClientEvent,
		"client_type", c.typ.String(),
		"client_id", clientId.String(),
		"height", height.String(),
	)

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

// QueryClientState returns the stored client state as a hex string.
func QueryClientState(clientId types.ClientId) string {
	c := store.getClient(clientId)
	if c == nil {
		return ""
	}

	return hexString(c.clientState)
}

// QueryConsensusState returns the consensus state at height as a hex string.
func QueryConsensusState(clientId types.ClientId, height types.Height) string {
	c := store.getClient(clientId)
	if c == nil {
		return ""
	}

	bz, found := c.getConsensusState(height)
	if !found {
		return ""
	}

	return hexString(bz)
}

// GetClientStatus returns the current status reported by a registered light client.
func GetClientStatus(clientId types.ClientId) types.Status {
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
