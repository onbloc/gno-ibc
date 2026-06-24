// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"

func main(cur realm) {
	clientId := realcometbls.CreateRealCometBLSClient(cross(cur))
	realcometbls.UpdateRealCometBLSClientWithTamperedHeader(cross(cur), clientId)
}

// Error:
// cometbls: cometblszk: invalid proof
