package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main() {
	clientId := realcometbls.CreateFrozenSyntheticCometBLSClient(cross)
	realadapter.Adapter{}.VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticMembershipProof(cross),
		realcometbls.SyntheticMembershipKey(cross),
		realcometbls.SyntheticMembershipValue(cross),
	)
}

// Error:
// cometbls: client is Frozen
