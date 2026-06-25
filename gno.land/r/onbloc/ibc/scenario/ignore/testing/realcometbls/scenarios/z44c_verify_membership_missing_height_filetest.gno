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
		types.NewHeight(uint64(realcometbls.DevnetHeight)),
		realcometbls.TwoExistenceProofStubs(cross(cur)),
		[]byte("key"),
		[]byte("value"),
	)
}

// Error:
// cometbls: consensus state not found at height 3405691582
