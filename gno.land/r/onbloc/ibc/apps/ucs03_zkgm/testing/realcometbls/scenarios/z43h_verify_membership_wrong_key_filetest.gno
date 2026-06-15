// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/onbloc/ibc/core"
	realadapter "gno.land/r/onbloc/ibc/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateSyntheticCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		realcometbls.SyntheticMembershipProof(cross(cur)),
		[]byte("packet-key-wrong"),
		realcometbls.SyntheticMembershipValue(cross(cur)),
	)
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
