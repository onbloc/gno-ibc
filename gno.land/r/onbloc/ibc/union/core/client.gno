package core

import (
	"chain"
	"chain/runtime"
	rtunsafe "chain/runtime/unsafe"
	"strings"

	"gno.land/p/onbloc/ibc/host"
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

// CreateClient creates a light client and stores its initial client and consensus states.
func CreateClient(cur realm, msg types.MsgCreateClient) types.ClientId {
	impl, ok := st.clientRegistry[msg.ClientType]
	if !ok {
		panic(ErrClientTypeNotFound)
	}

	clientId := st.generateClientId()
	impl.CreateClient(cross(cur), clientId, msg.ClientStateBytes, msg.ConsensusStateBytes)
	st.clientTypes[clientId] = msg.ClientType
	st.saveClientState(clientId, msg.ClientStateBytes)
	st.saveConsensusState(clientId, impl.GetLatestHeight(clientId), msg.ConsensusStateBytes)

	chain.Emit(CreateClientEvent,
		"client_id", clientId.String(),
		"client_type", msg.ClientType.String(),
	)
	return clientId
}

// UpdateClient updates a light client using the provided client message and stores the resulting state.
func UpdateClient(cur realm, msg types.MsgUpdateClient) types.Height {
	impl := st.getClient(msg.ClientId)

	update := impl.UpdateClient(cross(cur), msg.ClientId, msg.ClientMessage)

	st.saveClientState(msg.ClientId, update.ClientStateBytes)
	st.saveConsensusState(msg.ClientId, update.Height, update.ConsensusStateBytes)

	chain.Emit(UpdateClientEvent,
		"client_type", st.clientTypes[msg.ClientId].String(),
		"client_id", msg.ClientId.String(),
		"height", update.Height.String(),
	)
	return update.Height
}

// ForceUpdateClient updates the client and consensus states without verifying proofs.
//
// It is restricted to the admin and is intended for recovering expired or
// otherwise unrecoverable clients. It panics if the caller is not the admin
// or if the light client does not implement host.IForceLightClient.
func ForceUpdateClient(cur realm, msg types.MsgForceUpdateClient) types.Height {
	requireAdmin(cur, "ForceUpdateClient")

	impl, ok := st.getClient(msg.ClientId).(host.IForceLightClient)
	if !ok {
		panic("client does not support ForceUpdateClient")
	}

	runtime.AssertOriginCall()
	update := impl.ForceUpdateClient(cross(cur), msg.ClientId, msg.ClientStateBytes, msg.ConsensusStateBytes)

	st.saveClientState(msg.ClientId, update.ClientStateBytes)
	st.saveConsensusState(msg.ClientId, update.Height, update.ConsensusStateBytes)

	chain.Emit(UpdateClientEvent,
		"client_type", st.clientTypes[msg.ClientId].String(),
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

func requireActiveClient(client host.ILightClient, clientId types.ClientId) {
	if client.GetStatus(clientId) != types.StatusActive {
		panic(ErrClientNotActive)
	}
}

func verifyMembershipActive(clientId types.ClientId, height types.Height, proof, key, value []byte) {
	client := st.getClient(clientId)
	requireActiveClient(client, clientId)
	client.VerifyMembership(clientId, height, proof, key, value)
}

func verifyNonMembershipWithActiveClient(client host.ILightClient, clientId types.ClientId, height types.Height, proof, key []byte) {
	requireActiveClient(client, clientId)
	client.VerifyNonMembership(clientId, height, proof, key)
}

// RegisterClient registers a light client implementation for clientType.
//
// Known production client types must be registered by their owning light client
// realm. Other client types may only be registered under the caller realm's
// namespace.
func RegisterClient(cur realm, clientType types.ClientType, client host.ILightClient) {
	caller := cur.Previous().PkgPath()
	owner := clientTypeOwnerPath(clientType)
	if owner != "" {
		if caller != owner {
			panic("caller not authorized to register client: unauthorized")
		}
	} else if !isScopedClientType(caller, clientType) {
		panic("caller not authorized to register client: unauthorized")
	}
	st.registerClient(clientType, client)
	emitClientRegisteredEvent(clientType, caller, false)
}

// RegisterClientForType registers a light client implementation for clientType.
//
// It is restricted to the admin.
func RegisterClientForType(cur realm, clientType types.ClientType, client host.ILightClient) {
	requireAdmin(cur, "register client")
	runtime.AssertOriginCall()
	st.registerClient(clientType, client)
	emitClientRegisteredEvent(clientType, cur.Previous().PkgPath(), true)
}

// HasClient reports whether a light client is registered for clientType.
func HasClient(clientType types.ClientType) bool {
	_, ok := st.clientRegistry[clientType]
	return ok
}

// QueryClientState returns the stored client state as a hex string.
func QueryClientState(clientId types.ClientId) string {
	state, ok := st.clientStates[clientId]
	if !ok {
		return ""
	}
	return hexString(state)
}

// QueryConsensusState returns the consensus state at height as a hex string.
func QueryConsensusState(clientId types.ClientId, height types.Height) string {
	byHeight, ok := st.consensusStates[clientId]
	if !ok {
		return ""
	}
	state, ok := byHeight[height]
	if !ok {
		return ""
	}
	return hexString(state)
}

// GetClientStatus returns the current status reported by a registered light client.
func GetClientStatus(clientId types.ClientId) types.Status {
	if _, ok := st.clientTypes[clientId]; !ok {
		return types.StatusUnknown
	}
	return st.getClient(clientId).GetStatus(clientId)
}

// GetClientType returns the registered client type for clientId.
func GetClientType(clientId types.ClientId) string {
	clientType, ok := st.clientTypes[clientId]
	if !ok {
		return ""
	}
	return clientType.String()
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
