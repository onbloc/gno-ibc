// Package host defines the IBC host-environment contracts that core depends on:
// the light client interface (proof verification + client lifecycle). The
// contract lives in a pure package so light client adapters can implement it
// without importing the core realm, and core can route to them by interface.
package host

import "gno.land/p/onbloc/ibc/types"

// ILightClient defines the interface that light client adapters must implement.
// Methods that modify adapter state must declare _ realm as the first parameter
// (Gno crossing function requirement for cross(cur)-realm state writes).
type ILightClient interface {
	CreateClient(_ realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) string
	UpdateClient(_ realm, clientId types.ClientId, clientMessage []byte) types.ConsensusStateUpdate
	VerifyMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte, value []byte)
	VerifyNonMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte)
	GetTimestamp(clientId types.ClientId, height types.Height) types.Timestamp
	GetLatestHeight(clientId types.ClientId) types.Height
	GetStatus(clientId types.ClientId) types.Status
}

// IForceLightClient is an optional interface implemented by light clients that
// support admin-initiated force updates (e.g. to recover an expired client).
// It is separate from ILightClient because force-update is not part of the
// standard light client spec — it is a chain-operator escape hatch.
type IForceLightClient interface {
	ForceUpdateClient(cur realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) types.ConsensusStateUpdate
}
