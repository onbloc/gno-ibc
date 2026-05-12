package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main() {
	clientId := realcometbls.CreateRealCometBLSClient(cross)
	realadapter.Adapter{}.VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticMembershipProof(cross),
		realcometbls.SyntheticMembershipKey(cross),
		realcometbls.SyntheticMembershipValue(cross),
	)
}

// Error:
// cometbls: membership verification failed: cometbls: proof root does not match consensus state root
