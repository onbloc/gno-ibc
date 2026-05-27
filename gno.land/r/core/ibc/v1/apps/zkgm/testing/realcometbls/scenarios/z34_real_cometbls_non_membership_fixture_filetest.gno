// PKGPATH: gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateSyntheticCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyNonMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticNonMembershipProof(cross(cur)),
		realcometbls.SyntheticNonMembershipKey(cross(cur)),
	)

	println("non_membership_fixture", "ok")
}

// Output:
// non_membership_fixture ok
