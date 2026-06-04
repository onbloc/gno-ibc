// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateRealCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyNonMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.TwoExistenceProofStubs(cross(cur)),
		[]byte("key"),
	)
}

// Error:
// cometbls: non-membership verification failed: cometbls: first proof must be a non-existence proof
