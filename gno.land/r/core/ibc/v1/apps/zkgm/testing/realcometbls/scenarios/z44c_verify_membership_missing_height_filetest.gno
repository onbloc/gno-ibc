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
		core.Height(realcometbls.DevnetHeight),
		realcometbls.TwoExistenceProofStubs(cross),
		[]byte("key"),
		[]byte("value"),
	)
}

// Error:
// cometbls: membership verification failed: cometbls: consensus state not found at height
