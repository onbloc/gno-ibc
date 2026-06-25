// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	realadapter "gno.land/r/onbloc/ibc/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateRealCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyMembership(
		clientId,
		types.NewHeight(0, uint64(realcometbls.DevnetHeight-1)),
		realcometbls.OneExistenceProofStub(cross(cur)),
		[]byte("key"),
		[]byte("value"),
	)
}

// Error:
// cometbls: membership verification failed: cometbls: proof count does not match spec count
