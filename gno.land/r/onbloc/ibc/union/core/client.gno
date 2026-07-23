package core

import (
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// clientLoaders is the allowlist of realm package paths permitted to supply a
// light-client implementation through RegisterClient. It is seeded at init with
// the known loader realms and extended at runtime via RegisterClientLoader
// (admin-gated).
//
// Without this gate, any RelayerRole holder could register an arbitrary
// function value as a light client and forge every IBC proof. Union's cosmwasm
// core registers a contract *address* (already-deployed, audited bytecode); the
// Gno port accepts a first-class function value, so the caller must be bounded
// to a trusted loader realm whose source is reviewed. Admin callers (full
// trust) bypass the allowlist so they can install new client types during
// recovery and in tests.
var clientLoaders = map[string]bool{
	"gno.land/r/onbloc/ibc/union/lightclients/cometbls":           true,
	"gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt": true,
}

// RegisterClientLoader authorizes loaderPath to call RegisterClient. It is
// admin-gated (the selector defaults to AdminRole because it is not in the
// relayer selector set).
func RegisterClientLoader(cur realm, loaderPath string) {
	access.AssertCanCall(0, cur, SelectorRegisterClientLoader)

	clientLoaders[loaderPath] = true
}

// assertRegisteredLoader panics unless the calling realm is an approved loader
// or the caller holds AdminRole. Admin is fully trusted and may register client
// implementations directly (recovery, testing); relayer callers must come from
// an approved loader realm.
func assertRegisteredLoader(cur realm) {
	caller := cur.Previous().Address()
	if access.HasRole(manager.AdminRole, caller).IsMember {
		return
	}
	if !clientLoaders[cur.Previous().PkgPath()] {
		panic(makeError(ErrUnregisteredClientLoader, cur.Previous().PkgPath()))
	}
}

// HasClient reports whether a light client is registered for a client type.
func HasClient(clientType types.ClientType) bool {
	return mustGetImpl().HasClient(clientType)
}

// RegisterClient registers a light client implementation for a client type,
// delegating to the installed impl.
//
// The caller must be an approved loader realm (see clientLoaders) in addition
// to holding RelayerRole. This prevents a relayer from supplying an arbitrary
// function value as a light client and forging IBC proofs.
//
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L849-L865
func RegisterClient(cur realm, clientType types.ClientType, clientImpl lightclient.ClientImpl) {
	access.AssertCanCall(0, cur, SelectorRegisterClient)
	assertRegisteredLoader(cur)
	mustGetImpl().RegisterClient(0, cur, clientType, clientImpl)
}

// CreateClient assigns a client id, stores the submitted state bytes, then lets
// the light client verify creation against that freshly stored state.
//
// Union references:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L867-L903
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L905-L972
func CreateClient(cur realm, msg types.MsgCreateClient) {
	access.AssertCanCall(0, cur, SelectorCreateClient)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().CreateClient(0, cur, msg)
}

// UpdateClient verifies a client message against the light client object, which
// updates its own state, and mirrors the resulting state bytes for queries and
// counterparty proofs.
//
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L975-L1046
func UpdateClient(cur realm, msg types.MsgUpdateClient) {
	access.AssertCanCall(0, cur, SelectorUpdateClient)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().UpdateClient(0, cur, msg)
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
func ForceUpdateClient(cur realm, msg types.MsgForceUpdateClient) {
	access.AssertCanCall(0, cur, SelectorForceUpdateClient)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().ForceUpdateClient(0, cur, msg)
}

// Misbehaviour freezes a client after a valid misbehaviour proof, delegating to
// the installed impl.
//
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L1048-L1093
func Misbehaviour(cur realm, msg types.MsgMisbehaviour) {
	access.AssertCanCall(0, cur, SelectorMisbehaviour)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().Misbehaviour(0, cur, msg)
}
