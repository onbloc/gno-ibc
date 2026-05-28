package core

import (
	"chain"
	"chain/runtime"
	rtunsafe "chain/runtime/unsafe"
	"strings"
)

var deployer address

func init(cur realm) {
	deployer = rtunsafe.OriginCaller()
}

func isDeployer() bool {
	return rtunsafe.OriginCaller() == deployer
}

func assertDeployer(action string) {
	if !isDeployer() {
		panic("caller not authorized to " + action + ": unauthorized")
	}
}

func clientTypeOwnerPath(clientType ClientType) string {
	switch clientType {
	case ClientType("cometbls"):
		return "gno.land/r/core/ibc/v1/lightclients/cometbls"
	case ClientType("state-lens/ics23/mpt"):
		return "gno.land/r/core/ibc/v1/lightclients/statelensics23mpt"
	}
	return ""
}

func isScopedClientType(caller string, clientType ClientType) bool {
	return strings.HasPrefix(string(clientType), caller+"/")
}

func CreateClient(cur realm, msg MsgCreateClient) ClientId {
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

func UpdateClient(cur realm, msg MsgUpdateClient) Height {
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
// This method is restricted to the deployer and is intended only for recovering
// expired or otherwise unrecoverable clients.
//
// ForceUpdateClient panics if the caller is not the deployer.
//
// ForceUpdateClient panics if the underlying light client does not implement
// IForceLightClient.
func ForceUpdateClient(cur realm, msg MsgForceUpdateClient) Height {
	assertDeployer("ForceUpdateClient")

	impl, ok := st.getClient(msg.ClientId).(IForceLightClient)
	if !ok {
		panic("client does not support ForceUpdateClient")
	}

	// AssertOriginCall prevents re-entrancy through intermediate realms.
	//
	// Without this check, a contract invoked by the deployer within the same
	// transaction could hijack this entrypoint via tx.origin phishing.
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

// VerifyClientMembership verifies a membership proof against a registered
// light client without committing the verified value into this realm's state.
// State-lens light clients use this during UpdateClient to prove that an L2
// consensus state is stored in the L1 state tracked by another client.
func VerifyClientMembership(_ realm, clientId ClientId, proofHeight Height, proof, path, value []byte) {
	st.getClient(clientId).VerifyMembership(clientId, proofHeight, proof, path, value)
}

// GetClientStatus returns the current status reported by a registered light
// client. Lens clients use this to mirror the status of the underlying L1
// client they depend on.
func GetClientStatus(clientId ClientId) Status {
	if _, ok := st.clientTypes[clientId]; !ok {
		return StatusUnknown
	}
	return st.getClient(clientId).GetStatus(clientId)
}

func QueryClientState(clientId ClientId) string {
	state, ok := st.clientStates[clientId]
	if !ok {
		return ""
	}
	return hexString(state)
}

func GetClientType(clientId ClientId) string {
	clientType, ok := st.clientTypes[clientId]
	if !ok {
		return ""
	}
	return clientType.String()
}

func QueryConsensusState(clientId ClientId, height Height) string {
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

// RegisterClient registers a light client implementation under the given client
// type. Known production client types must be registered by their owning light
// client realm. Other client types may only be registered under the caller
// realm's namespace.
func RegisterClient(cur realm, clientType ClientType, client ILightClient) {
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
}

// RegisterClientForType registers a light client implementation for an explicit
// client type through a privileged deployer call.
func RegisterClientForType(cur realm, clientType ClientType, client ILightClient) {
	assertDeployer("register client")
	runtime.AssertOriginCall()
	st.registerClient(clientType, client)
}

// HasClient reports whether a light client is registered for clientType.
func HasClient(clientType ClientType) bool {
	_, ok := st.clientRegistry[clientType]
	return ok
}
