package main

import (
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	clientId := realcometbls.CreateZ35CometBLSClient(cross(cur))
	connectionId := openConnection(clientId, realcometbls.Z35ConnectionTryProof(cross(cur)))
	channelId := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), []byte(zkgm.ProxyPkgPath()), []byte(zkgm.ProxyPkgPath()), connectionId, zkgm.Version))

	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), channelId, zkgm.Version, core.ChannelId(3), realcometbls.Z35ChannelTryProof(cross(cur)), core.Height(realcometbls.DevnetHeight - 1)))
}

func openConnection(clientId core.ClientId, proof []byte) core.ConnectionId {
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), proof, core.Height(realcometbls.DevnetHeight - 1)))
	return connectionId
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
