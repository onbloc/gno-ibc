// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/onbloc/ibc/core"
	realadapter "gno.land/r/onbloc/ibc/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateExpiredSyntheticCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticMembershipProof(cross(cur)),
		realcometbls.SyntheticMembershipKey(cross(cur)),
		realcometbls.SyntheticMembershipValue(cross(cur)),
	)
}

// Error:
// cometbls: client is Expired
