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
	clientId := realcometbls.CreateZ42WrongVersionCometBLSClient(cross(cur))
	connectionId := openConnection(cur, clientId, realcometbls.Z42WrongVersionConnectionTryProof(cross(cur)))
	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit([]byte(zkgm.ProxyPkgPath()), []byte(zkgm.ProxyPkgPath()), connectionId, zkgm.Version, "g1msgrelayer"))

	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, "bad-version", types.ChannelId(2), realcometbls.Z42WrongVersionChannelTryProof(cross(cur)), uint64(realcometbls.DevnetHeight-1), "g1msgrelayer"))
}

func openConnection(cur realm, clientId types.ClientId, proof []byte) types.ConnectionId {
	connectionId := core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), proof, uint64(realcometbls.DevnetHeight-1)))
	return connectionId
}

// Error:
// zkgm: unsupported channel version
