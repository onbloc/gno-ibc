// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateZ35CometBLSClient(cross(cur))
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))

	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(78), realcometbls.Z35ConnectionTryProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
