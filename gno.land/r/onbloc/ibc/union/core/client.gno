package core

import (
	"chain"
	"chain/runtime"
	rtunsafe "chain/runtime/unsafe"
	"strings"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

var admin address

func init(cur realm) {
	// SAFE: admin bootstrap needs the tx signer, not a loader realm that may
	// appear as cur.Previous().
	admin = rtunsafe.OriginCaller()
}

// GetAdmin returns the current admin address.
func GetAdmin() address {
	return admin
}

// SetAdmin transfers admin rights to a new address. Only callable by the current admin.
func SetAdmin(cur realm, newAdmin address) {
	runtime.AssertOriginCall()
	requireAdmin(cur, "set admin")
	oldAdmin := admin
	admin = newAdmin
	emitAdminChangedEvent(oldAdmin, newAdmin)
}

func requireAdmin(cur realm, action string) {
	if cur.Previous().Address() != admin {
		panic("caller not authorized to " + action + ": unauthorized")
	}
}

// CreateClient creates a light client through the registered light client adapter.
func CreateClient(cur realm, msg types.MsgCreateClient) types.ClientId {
	creator := cur.Previous().Address()
	c := store.addClient(msg.ClientType, creator)
	clientId := c.id
	c.lightClient.CreateClient(cross(cur), clientId, msg.ClientStateBytes, msg.ConsensusStateBytes)

	chain.Emit(CreateClientEvent,
		"client_id", clientId.String(),
		"client_type", msg.ClientType.String(),
	)
	return clientId
}

// UpdateClient updates a light client using the provided client message and stores the resulting state.
func UpdateClient(cur realm, msg types.MsgUpdateClient) types.Height {
	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}
	update := c.lightClient.UpdateClient(cross(cur), msg.ClientId, msg.ClientMessage)

	c.saveState(update.ClientStateBytes)
	c.saveConsensusState(update.Height, update.ConsensusStateBytes)

	chain.Emit(UpdateClientEvent,
		"client_type", c.typ.String(),
		"client_id", msg.ClientId.String(),
		"height", update.Height.String(),
	)
	return update.Height
}

// ForceUpdateClient updates the client and consensus states without verifying proofs.
//
// It is restricted to the admin and is intended for recovering expired or
// otherwise unrecoverable clients. It panics if the caller is not the admin
// or if the light client does not implement lightclient.IForceLightClient.
func ForceUpdateClient(cur realm, msg types.MsgForceUpdateClient) types.Height {
	requireAdmin(cur, "ForceUpdateClient")

	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}
	impl, ok := c.lightClient.(lightclient.IForceLightClient)
	if !ok {
		panic("client does not support ForceUpdateClient")
	}

	runtime.AssertOriginCall()
	update := impl.ForceUpdateClient(cross(cur), msg.ClientId, msg.ClientStateBytes, msg.ConsensusStateBytes)

	c.saveState(update.ClientStateBytes)
	c.saveConsensusState(update.Height, update.ConsensusStateBytes)

	chain.Emit(UpdateClientEvent,
		"client_type", c.typ.String(),
		"client_id", msg.ClientId.String(),
		"height", update.Height.String(),
	)
	return update.Height
}

// VerifyClientMembership verifies a membership proof against a registered light client.
//
// It does not commit the verified value into this realm's state.
func VerifyClientMembership(_ realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte) {
	verifyMembershipActive(clientId, proofHeight, proof, path, value)
}

func requireActiveClient(impl lightclient.ILightClient, clientId types.ClientId) {
	if impl.GetStatus(clientId) != types.StatusActive {
		panic(ErrClientNotActive)
	}
}

func verifyMembershipActive(clientId types.ClientId, height types.Height, proof, key, value []byte) {
	c := store.getClient(clientId)
	if c == nil {
		panic("client " + clientId.String() + " not found")
	}
	requireActiveClient(c.lightClient, clientId)
	c.lightClient.VerifyMembership(clientId, height, proof, key, value)
}

func verifyNonMembershipWithActiveClient(impl lightclient.ILightClient, clientId types.ClientId, height types.Height, proof, key []byte) {
	requireActiveClient(impl, clientId)
	impl.VerifyNonMembership(clientId, height, proof, key)
}

// RegisterClient registers a light client implementation for clientType.
//
// Known production client types must be registered by their owning light client
// realm. Other client types may only be registered under the caller realm's
// namespace.
func RegisterClient(cur realm, clientType types.ClientType, client lightclient.ILightClient) {
	caller := cur.Previous().PkgPath()
	owner := clientTypeOwnerPath(clientType)
	if owner != "" {
		if caller != owner {
			panic("caller not authorized to register client: unauthorized")
		}
	} else if !isScopedClientType(caller, clientType) {
		panic("caller not authorized to register client: unauthorized")
	}
	store.registerClient(clientType, client)
	emitClientRegisteredEvent(clientType, caller, false)
}

// RegisterClientForType registers a light client implementation for clientType.
//
// It is restricted to the admin.
func RegisterClientForType(cur realm, clientType types.ClientType, client lightclient.ILightClient) {
	requireAdmin(cur, "register client")
	runtime.AssertOriginCall()
	store.registerClient(clientType, client)
	emitClientRegisteredEvent(clientType, cur.Previous().PkgPath(), true)
}

// HasClient reports whether a light client is registered for clientType.
func HasClient(clientType types.ClientType) bool {
	_, ok := store.clientRegistry[clientType]
	return ok
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
	return c.lightClient.GetStatus(clientId)
}

// GetClientType returns the registered client type for clientId.
func GetClientType(clientId types.ClientId) string {
	c := store.getClient(clientId)
	if c == nil {
		return ""
	}
	return c.typ.String()
}

func clientTypeOwnerPath(clientType types.ClientType) string {
	switch clientType {
	case types.ClientType("cometbls"):
		return "gno.land/r/onbloc/ibc/lightclients/cometbls"
	case types.ClientType("state-lens/ics23/mpt"):
		return "gno.land/r/onbloc/ibc/lightclients/state_lens/ics23_mpt"
	}
	return ""
}

func isScopedClientType(caller string, clientType types.ClientType) bool {
	return strings.HasPrefix(string(clientType), caller+"/")
}
