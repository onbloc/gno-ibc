package core

import (
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// types.gno declares the upgradeable-proxy contracts for the IBC host, mirroring
// the apps/ucs03_zkgm split. core is the proxy: it owns the stable identity
// (admin, package address/path), the Store, and the app registry, and delegates
// its logic to the installed impl. Read-only queries stay on the proxy.
//
// The migration is incremental. ICore/IStore currently cover the client
// subsystem; connection, channel, and packet handling follow the same shape.

// ICore is the swappable implementation surface. Methods use the non-crossing
// (_ int, rlm realm, ...) threading form so the impl executes in the proxy's
// ownership context (interrealm borrow rule), letting it mutate the proxy-owned
// store and emit host events as core.
type ICore interface {
	// SetStore injects the proxy-owned store. UpdateImpl calls it at install time
	// so the store stays private to the proxy (no public store getter).
	SetStore(_ int, rlm realm, store IStore)

	// --- Client subsystem ---
	CreateClient(_ int, rlm realm, clientType types.ClientType, lc lightclient.Interface) types.ClientId
	UpdateClient(_ int, rlm realm, msg types.MsgUpdateClient) types.Height
	ForceUpdateClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) types.Height
	VerifyClientMembership(_ int, rlm realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte)
}

// IStore is the proxy-owned persistent state injected into the impl. Setters take
// the borrow-rule (_ int, rlm realm, ...) form; getters are plain. The nested
// per-client structure (consensus/connection/channel/batch trees, chain-param
// commitment mirror) stays private to the Store — the impl operates by clientId,
// so the encapsulation survives impl upgrades.
type IStore interface {
	// --- Client subsystem ---
	AddClient(_ int, rlm realm, typ types.ClientType, creator address, lc lightclient.Interface) types.ClientId
	ClientExists(clientId types.ClientId) bool
	ClientType(clientId types.ClientId) (types.ClientType, bool)
	GetLightClient(clientId types.ClientId) (lightclient.Interface, bool)
	SetLightClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) bool
	SaveClientState(_ int, rlm realm, clientId types.ClientId, clientStateBytes []byte) bool
	SaveConsensusState(_ int, rlm realm, clientId types.ClientId, height types.Height, consensusStateBytes []byte) bool
}
