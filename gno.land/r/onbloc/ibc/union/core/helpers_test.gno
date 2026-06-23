package core

import (
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

func requireSelectorProtectedForTest(cur realm, selector manager.Selector) {
	if role := access.GetFunctionRole(cross(cur), selector); role == manager.PublicRole {
		panic("test selector must not be public")
	}
}

func queryClientStateHex(clientId types.ClientId) string {
	bz, err := GetClientState(clientId)
	if err != nil {
		return ""
	}
	return hexString(bz)
}

func queryConsensusStateHex(clientId types.ClientId, height uint64) string {
	bz, err := GetConsensusState(clientId, types.NewHeight(height))
	if err != nil {
		return ""
	}
	return hexString(bz)
}
