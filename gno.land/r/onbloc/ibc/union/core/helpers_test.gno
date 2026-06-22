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

func VerifyClientMembership(_ realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte) {
	verifyMembershipActive(clientId, proofHeight, proof, path, value)
}
