// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/onbloc/unionibc/v1/core"
	realadapter "gno.land/r/onbloc/unionibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateFrozenSyntheticCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticMembershipProof(cross(cur)),
		realcometbls.SyntheticMembershipKey(cross(cur)),
		realcometbls.SyntheticMembershipValue(cross(cur)),
	)
}

// Error:
// cometbls: client is Frozen
