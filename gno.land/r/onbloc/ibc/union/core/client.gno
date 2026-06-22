package core

import (
	"chain/runtime"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// RegisterClient registers a light client implementation for a client type,
// delegating to the installed impl.
//
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L849-L865
func RegisterClient(cur realm, clientType types.ClientType, lc lightclient.Interface) {
	getImpl().RegisterClient(0, cur, clientType, lc)
}

// HasClient reports whether a light client is registered for a client type.
func HasClient(clientType types.ClientType) bool {
	return getImpl().HasClient(clientType)
}

// CreateClient assigns a client id for a registered light client type, stores
// the submitted state bytes, then lets the light client verify creation against
// that freshly stored state.
//
// Union references:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L867-L903
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L905-L972
func CreateClient(cur realm, msg types.MsgCreateClient) types.ClientId {
	return getImpl().CreateClient(0, cur, msg)
}

// UpdateClient verifies a client message against the light client object, which
// updates its own state, and mirrors the resulting state bytes for queries and
// counterparty proofs.
//
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L975-L1046
func UpdateClient(cur realm, msg types.MsgUpdateClient) types.Height {
	return getImpl().UpdateClient(0, cur, msg)
}

// ForceUpdateClient re-initializes a client from submitted state bytes,
// bypassing header proof verification.
//
// It is restricted to the admin and recovers expired or otherwise unrecoverable
// clients. The registered light client type for the existing client is reused.
//
// Union references:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L146-L166
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L905-L972
func ForceUpdateClient(cur realm, msg types.MsgForceUpdateClient) types.Height {
	requireAdmin(cur, "ForceUpdateClient")
	runtime.AssertOriginCall()
	return getImpl().ForceUpdateClient(0, cur, msg)
}

// VerifyClientMembership verifies a membership proof against a registered light
// client. It does not commit the verified value into this realm's state.
func VerifyClientMembership(cur realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte) {
	getImpl().VerifyClientMembership(0, cur, clientId, proofHeight, proof, path, value)
}

// requireActiveClient panics unless the client's light client reports Active.
// Used by the proxy-resident admin recovery (Force*) handshake paths.
func requireActiveClient(c *client) {
	if c.lightClient.Status().ToType() != types.StatusActive {
		panic(ErrClientNotActive)
	}
}

// verifyMembershipActive verifies a membership proof against an active client,
// used by the proxy-resident Force* connection/channel handshake paths.
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

// verifyNonMembershipWithActiveClient verifies a non-membership proof against an
// already-fetched active client, used by the proxy-resident Force* paths.
func verifyNonMembershipWithActiveClient(c *client, height types.Height, proof, key []byte) {
	requireActiveClient(c)

	if err := c.lightClient.VerifyNonMembership(height.RevisionHeight, key, proof); err != nil {
		panic(err)
	}
}
