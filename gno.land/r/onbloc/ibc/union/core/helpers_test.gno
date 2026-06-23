package core

import "gno.land/p/onbloc/ibc/union/types"

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
