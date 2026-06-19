package impl

import (
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// CreateClient registers a new light client object and verifies its creation.
// The creator is the realm that invoked the host (proxy) entrypoint.
func (c *coreV1) CreateClient(_ int, rlm realm, clientType types.ClientType, lc lightclient.Interface) types.ClientId {
	creator := rlm.Previous().Address()
	clientId := c.store.AddClient(0, rlm, clientType, creator, lc)

	if _, err := lc.VerifyCreation(creator, creator); err != nil {
		panic("create client: " + err.Error())
	}

	core.EmitCreateClient(clientId, clientType)
	return clientId
}

// UpdateClient verifies a client message against the light client object, which
// updates its own state, and mirrors the resulting state bytes for queries and
// counterparty proofs.
func (c *coreV1) UpdateClient(_ int, rlm realm, msg types.MsgUpdateClient) types.Height {
	lc, ok := c.store.GetLightClient(msg.ClientId)
	if !ok {
		panic("client " + msg.ClientId.String() + " not found")
	}

	caller := rlm.Previous().Address()
	update, err := lc.VerifyHeader(caller, msg.ClientMessage, caller)
	if err != nil {
		panic("update client: " + err.Error())
	}

	height := types.NewHeight(update.Height)
	if len(update.ClientStateBytes) != 0 {
		c.store.SaveClientState(0, rlm, msg.ClientId, update.ClientStateBytes)
	}
	if len(update.ConsensusStateBytes) != 0 {
		c.store.SaveConsensusState(0, rlm, msg.ClientId, height, update.ConsensusStateBytes)
	}

	clientType, _ := c.store.ClientType(msg.ClientId)
	core.EmitUpdateClient(clientType, msg.ClientId, height)
	return height
}

// VerifyClientMembership verifies a membership proof against a registered, active
// light client. It does not commit the verified value into the host state.
func (c *coreV1) VerifyClientMembership(_ int, rlm realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte) {
	lc, ok := c.store.GetLightClient(clientId)
	if !ok {
		panic("client " + clientId.String() + " not found")
	}
	if lc.Status() != lightclient.Active {
		panic(core.ErrClientNotActive)
	}
	if err := lc.VerifyMembership(proofHeight.RevisionHeight, path, proof, value); err != nil {
		panic(err)
	}
}
