package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main() {
	clientId := realcometbls.CreateSyntheticCometBLSClient(cross)
	realadapter.Adapter{}.VerifyNonMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticNonMembershipProof(cross),
		realcometbls.SyntheticNonMembershipKey(cross),
	)

	println("non_membership_fixture", "ok")
}

// Output:
// non_membership_fixture ok
