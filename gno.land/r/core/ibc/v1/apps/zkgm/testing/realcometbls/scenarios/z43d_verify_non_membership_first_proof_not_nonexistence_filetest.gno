package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main() {
	clientId := realcometbls.CreateRealCometBLSClient(cross)
	realadapter.Adapter{}.VerifyNonMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.TwoExistenceProofStubs(cross),
		[]byte("key"),
	)
}

// Error:
// cometbls: non-membership verification failed: cometbls: first proof must be a non-existence proof
