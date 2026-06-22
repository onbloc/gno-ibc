package core

import (
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// RegisterClient registers a light client implementation for a client type.
//
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L849-L865
func RegisterClient(cur realm, clientType types.ClientType, lc lightclient.Interface) {
	requireCanCall(0, cur, SelectorRegisterClient)
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
//
// Union references:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L867-L903
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L905-L972
func CreateClient(cur realm, msg types.MsgCreateClient) {
	requireCanCall(0, cur, SelectorCreateClient)
	creator := cur.Previous().Address()
	lc, ok := store.registeredClient(msg.ClientType)
	if !ok {
		panic("client type not found")
	}

	clientId := store.nextClientId()
	c := store.addClient(clientId, msg.ClientType, creator, lc)
	initClient(creator, msg.ClientStateBytes, msg.ConsensusStateBytes, creator, clientId)

	emitCreateClientEvent(c.id, msg.ClientType, lc.GetCounterpartyChainID())
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
//
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L975-L1046
func UpdateClient(cur realm, msg types.MsgUpdateClient) {
	requireCanCall(0, cur, SelectorUpdateClient)
	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}

	requireActiveClient(c)

	caller := cur.Previous().Address()
	update, err := c.lightClient.VerifyHeader(caller, msg.ClientMessage, caller)
	if err != nil {
		panic("update client: " + err.Error())
	}

	height := types.NewHeight(update.Height)
	if len(update.ClientStateBytes) != 0 {
		c.saveClientState(update.ClientStateBytes)
	}

	c.saveConsensusState(height, update.ConsensusStateBytes)
	for k, v := range update.StorageWrites {
		c.saveClientStore(k, v)
	}

	emitUpdateClientEvent(msg.ClientId, height)
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
	requireCanCall(0, cur, SelectorForceUpdateClient)

	c := store.getClient(msg.ClientId)
	if c == nil {
		panic("client " + msg.ClientId.String() + " not found")
	}

	caller := cur.Previous().Address()
	height := initClient(caller, msg.ClientStateBytes, msg.ConsensusStateBytes, caller, msg.ClientId)

	emitForceUpdateClientEvent(msg.ClientId, height)
}

func requireActiveClient(c *client) {
	if c.lightClient.Status().ToType() != types.StatusActive {
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

// GetClientState returns the stored client state bytes.
//
// Union query reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L2138-L2140
func GetClientState(clientId types.ClientId) []byte {
	c := store.getClient(clientId)
	if c == nil {
		return nil
	}

	return cloneBytes(c.clientState)
}

// GetConsensusState returns the consensus state bytes at height.
//
// Union query reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L2141-L2145
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

// GetLatestHeight returns the latest height reported by the light client.
//
// Union query reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L2129-L2137
func GetLatestHeight(clientId types.ClientId) uint64 {
	c := store.getClient(clientId)
	if c == nil {
		return 0
	}

	return c.lightClient.GetLatestHeight()
}

// GetTimestampAtHeight returns the light client's timestamp at a height.
//
// Union query references:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L2100-L2111
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L2126-L2128
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
//
// Union query reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L2146-L2154
func GetStatus(clientId types.ClientId) types.Status {
	c := store.getClient(clientId)
	if c == nil {
		return types.StatusUnknown
	}

	return c.lightClient.Status().ToType()
}

// GetClientType returns the registered client type for clientId.
//
// Union query reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/contract.rs#L2117-L2119
func GetClientType(clientId types.ClientId) string {
	c := store.getClient(clientId)
	if c == nil {
		return ""
	}

	return c.typ.String()
}
