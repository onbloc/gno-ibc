// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import realcometbls "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls"

func main(cur realm) {
	clientId := realcometbls.CreateRealCometBLSClient(cross(cur))
	realcometbls.UpdateRealCometBLSClientWithTamperedHeader(cross(cur), clientId)
}

// Error:
// cometbls: cometblszk: invalid proof
