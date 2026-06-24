// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	clientId := realcometbls.CreateZ35CometBLSClient(cross(cur))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))

	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(78), realcometbls.Z35ConnectionTryProof(cross(cur)), uint64(realcometbls.DevnetHeight-1)))
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
