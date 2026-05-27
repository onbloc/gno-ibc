package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main() {
	clientId := realcometbls.CreateSyntheticCometBLSClient(cross(cur))
	realadapter.Adapter{}.VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticMembershipWrongSubrootProof(cross(cur)),
		realcometbls.SyntheticMembershipKey(cross(cur)),
		realcometbls.SyntheticMembershipValue(cross(cur)),
	)
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided value doesn't match proof
