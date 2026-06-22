package impl

import (
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// RegisterClient records a light client object under a client type so it can be
// instantiated later by CreateClient. The caller must supply a non-nil object.
func (c *coreV1) RegisterClient(_ int, rlm realm, clientType types.ClientType, lc lightclient.Interface) {
	if lc == nil {
		panic("caller not authorized to register client: unauthorized")
	}
	c.store.RegisterClient(0, rlm, clientType, lc)
	core.EmitRegisterClient(clientType)
}

// HasClient reports whether a light client is registered for a client type.
func (c *coreV1) HasClient(clientType types.ClientType) bool {
	return c.store.HasRegisteredClient(clientType)
}

// CreateClient assigns a client id for a registered light client type, stores
// the submitted state bytes, then lets the light client verify creation against
// that freshly stored state.
func (c *coreV1) CreateClient(_ int, rlm realm, msg types.MsgCreateClient) {
	caller := rlm.Previous().Address()
	relayer := address(msg.Relayer)
	lc, ok := c.store.RegisteredClient(msg.ClientType)
	if !ok {
		panic("client type not found")
	}

	clientId := c.store.AddClient(0, rlm, msg.ClientType, caller, lc)
	c.initClient(0, rlm, caller, msg.ClientStateBytes, msg.ConsensusStateBytes, relayer, lc, clientId)

	core.EmitCreateClient(clientId, msg.ClientType, lc.GetCounterpartyChainID())
}

// initClient mirrors the submitted client/consensus state for a stored client,
// runs the light client's creation verification, then persists any state
// overwrite and storage writes the verification returns. It returns the height
// the consensus state was stored at.
func (c *coreV1) initClient(_ int, rlm realm, caller address, clientStateBytes, consensusStateBytes []byte, relayer address, lc lightclient.Interface, clientId types.ClientId) types.Height {
	c.store.SaveClientState(0, rlm, clientId, clientStateBytes)
	height := types.NewHeight(lc.GetLatestHeight())
	c.store.SaveConsensusState(0, rlm, clientId, height, consensusStateBytes)

	result, err := lc.VerifyCreation(caller, relayer)
	if err != nil {
		panic("create client: " + err.Error())
	}

	if len(result.ClientStateBytes) != 0 {
		c.store.SaveClientState(0, rlm, clientId, result.ClientStateBytes)
	}
	for k, v := range result.StorageWrites {
		c.store.SaveClientStore(0, rlm, clientId, k, v)
	}

	return height
}

// UpdateClient verifies a client message against the light client object, which
// updates its own state, and mirrors the resulting state bytes for queries and
// counterparty proofs.
func (c *coreV1) UpdateClient(_ int, rlm realm, msg types.MsgUpdateClient) {
	lc, ok := c.store.GetLightClient(msg.ClientId)
	if !ok {
		panic("client " + msg.ClientId.String() + " not found")
	}
	if lc.Status() != lightclient.Active {
		panic(core.ErrClientNotActive)
	}

	caller := rlm.Previous().Address()
	relayer := address(msg.Relayer)
	update, err := lc.VerifyHeader(caller, msg.ClientMessage, relayer)
	if err != nil {
		panic("update client: " + err.Error())
	}

	height := types.NewHeight(update.Height)
	if len(update.ClientStateBytes) != 0 {
		c.store.SaveClientState(0, rlm, msg.ClientId, update.ClientStateBytes)
	}
	// Union stores consensus_state_bytes unconditionally because the field is not
	// optional in the update response.
	c.store.SaveConsensusState(0, rlm, msg.ClientId, height, update.ConsensusStateBytes)
	for k, v := range update.StorageWrites {
		c.store.SaveClientStore(0, rlm, msg.ClientId, k, v)
	}

	core.EmitUpdateClient(msg.ClientId, height)
}

// ForceUpdateClient re-initializes a client from submitted state bytes,
// bypassing header proof verification. The admin gate lives on the proxy; the
// registered light client object for the existing client is reused.
func (c *coreV1) ForceUpdateClient(_ int, rlm realm, msg types.MsgForceUpdateClient) {
	lc, ok := c.store.GetLightClient(msg.ClientId)
	if !ok {
		panic("client " + msg.ClientId.String() + " not found")
	}

	// Union reuses info.sender as both caller and relayer for the force path
	// (contract.rs L150-159: init_client(.., info.sender, client_impl, client_id)).
	caller := rlm.Previous().Address()
	height := c.initClient(0, rlm, caller, msg.ClientStateBytes, msg.ConsensusStateBytes, caller, lc, msg.ClientId)

	core.EmitForceUpdateClient(msg.ClientId, height)
}

// Misbehaviour verifies a misbehaviour message against an active light client and
// freezes it. The gno light client freezes its own in-memory state (persisted by
// reference through the store), so unlike union the host does not mirror/commit
// the frozen client-state bytes; it only invokes the client and emits the event.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L1048-L1093
func (c *coreV1) Misbehaviour(_ int, rlm realm, msg types.MsgMisbehaviour) {
	lc, ok := c.store.GetLightClient(msg.ClientId)
	if !ok {
		panic("client " + msg.ClientId.String() + " not found")
	}
	if lc.Status() != lightclient.Active {
		panic(core.ErrClientNotActive)
	}

	caller := rlm.Previous().Address()
	relayer := address(msg.Relayer)
	if _, err := lc.Misbehaviour(caller, msg.ClientMessage, relayer); err != nil {
		panic("misbehaviour: " + err.Error())
	}

	core.EmitMisbehaviour(msg.ClientId)
}

// VerifyClientMembership verifies a membership proof against a registered, active
// light client. It does not commit the verified value into the host state.
func (c *coreV1) VerifyClientMembership(_ int, rlm realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte) {
	c.verifyMembership(clientId, proofHeight, proof, path, value)
}

// verifyMembership checks a membership proof against a registered, active light
// client. Shared by VerifyClientMembership and the connection/channel handshakes.
func (c *coreV1) verifyMembership(clientId types.ClientId, height types.Height, proof, key, value []byte) {
	lc, ok := c.store.GetLightClient(clientId)
	if !ok {
		panic("client " + clientId.String() + " not found")
	}
	if lc.Status() != lightclient.Active {
		panic(core.ErrClientNotActive)
	}
	if err := lc.VerifyMembership(height.RevisionHeight, key, proof, value); err != nil {
		panic(err)
	}
}
