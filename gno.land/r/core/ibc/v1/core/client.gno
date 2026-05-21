package core

import "chain"

func CreateClient(_ realm, msg MsgCreateClient) ClientId {
	impl, ok := st.clientRegistry[msg.ClientType]
	if !ok {
		panic(ErrClientTypeNotFound)
	}

	clientId := st.generateClientId()
	impl.CreateClient(cross, clientId, msg.ClientStateBytes, msg.ConsensusStateBytes)
	st.clientTypes[clientId] = msg.ClientType
	st.saveClientState(clientId, msg.ClientStateBytes)
	st.saveConsensusState(clientId, impl.GetLatestHeight(clientId), msg.ConsensusStateBytes)

	chain.Emit(CreateClientEvent,
		"client_id", clientId.String(),
		"client_type", msg.ClientType.String(),
	)
	return clientId
}

func UpdateClient(_ realm, msg MsgUpdateClient) Height {
	impl := st.getClient(msg.ClientId)

	update := impl.UpdateClient(cross, msg.ClientId, msg.ClientMessage)

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

// RegisterClient registers a light client implementation under the given
// client type. Apps and chain operators call this from a loader realm at init.
func RegisterClient(_ realm, clientType ClientType, client ILightClient) {
	st.registerClient(clientType, client)
}

// HasClient reports whether a light client is registered for clientType.
func HasClient(clientType ClientType) bool {
	_, ok := st.clientRegistry[clientType]
	return ok
}
