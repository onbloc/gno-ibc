package core

import "gno.land/p/onbloc/ibc/union/types"

func queryClientStateHex(clientId types.ClientId) string {
	bz := GetClientState(clientId)
	if len(bz) == 0 {
		return ""
	}
	return hexString(bz)
}

func queryConsensusStateHex(clientId types.ClientId, height uint64) string {
	bz := GetConsensusState(clientId, height)
	if len(bz) == 0 {
		return ""
	}
	return hexString(bz)
}
