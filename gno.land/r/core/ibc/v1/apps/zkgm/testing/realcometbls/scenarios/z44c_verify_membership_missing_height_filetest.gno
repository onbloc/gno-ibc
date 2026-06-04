// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/onbloc/unionibc/v1/core"
	realadapter "gno.land/r/onbloc/unionibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateRealCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight),
		realcometbls.TwoExistenceProofStubs(cross(cur)),
		[]byte("key"),
		[]byte("value"),
	)
}

// Error:
// cometbls: consensus state not found at height 3405691582
