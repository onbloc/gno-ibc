// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
	clientId := realcometbls.CreateZ35CometBLSClient(cross(cur))
	connectionId := openConnection(cur, clientId, realcometbls.Z35ConnectionTryProof(cross(cur)))
	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit([]byte(zkgm.ProxyPkgPath()), []byte(zkgm.ProxyPkgPath()), connectionId, zkgm.Version))

	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(3), realcometbls.Z35ChannelTryProof(cross(cur)), uint64(realcometbls.DevnetHeight-1)))
}

func openConnection(cur realm, clientId types.ClientId, proof []byte) types.ConnectionId {
	connectionId := core.NextConnectionId()
	core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), proof, uint64(realcometbls.DevnetHeight-1)))
	return connectionId
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
