package core

import "gno.land/p/onbloc/ibc/union/types"

func queryClientStateHex(clientId types.ClientId) string {
	bz, ok := GetClientState(clientId)
	if !ok {
		return ""
	}
	return hexString(bz)
}

func queryConsensusStateHex(clientId types.ClientId, height uint64) string {
	bz, ok := GetConsensusState(clientId, types.NewHeight(height))
	if !ok {
		return ""
	}
	return hexString(bz)
}
