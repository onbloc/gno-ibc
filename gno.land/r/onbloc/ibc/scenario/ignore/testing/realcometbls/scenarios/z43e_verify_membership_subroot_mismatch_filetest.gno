// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	realadapter "gno.land/r/onbloc/ibc/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateSyntheticCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyMembership(
		clientId,
		types.NewHeight(0, uint64(realcometbls.DevnetHeight-1)),
		realcometbls.SyntheticMembershipWrongSubrootProof(cross(cur)),
		realcometbls.SyntheticMembershipKey(cross(cur)),
		realcometbls.SyntheticMembershipValue(cross(cur)),
	)
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided value doesn't match proof
