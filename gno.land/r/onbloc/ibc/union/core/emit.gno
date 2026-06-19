package core

import (
	"chain"

	"gno.land/p/onbloc/ibc/union/types"
)

// emit.gno exposes the host event emitters the injected impl calls so that
// events are emitted from the core (proxy) realm, keeping the IBC host as the
// stable event source across impl upgrades. Mirrors EmitRecvError used by the
// ucs03_zkgm impl.

// EmitCreateClient emits the CreateClient host event.
func EmitCreateClient(clientId types.ClientId, clientType types.ClientType) {
	chain.Emit(
		CreateClientEvent,
		"client_id", clientId.String(),
		"client_type", clientType.String(),
	)
}

// EmitUpdateClient emits the UpdateClient host event.
func EmitUpdateClient(clientType types.ClientType, clientId types.ClientId, height types.Height) {
	chain.Emit(
		UpdateClientEvent,
		"client_type", clientType.String(),
		"client_id", clientId.String(),
		"height", height.String(),
	)
}
