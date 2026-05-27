package main

import (
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	clientId := realcometbls.CreateZ42WrongVersionCometBLSClient(cross(cur))
	connectionId := openConnection(clientId, realcometbls.Z42WrongVersionConnectionTryProof(cross(cur)))
	channelId := core.ChannelOpenInit(cross(cur), core.MsgChannelOpenInit{
		PortId:             []byte(zkgm.ProxyPkgPath()),
		CounterpartyPortId: []byte(zkgm.ProxyPkgPath()),
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})

	core.ChannelOpenAck(cross(cur), core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   "bad-version",
		CounterpartyChannelId: core.ChannelId(2),
		ProofTry:              realcometbls.Z42WrongVersionChannelTryProof(cross(cur)),
		ProofHeight:           core.Height(realcometbls.DevnetHeight - 1),
	})
}

func openConnection(clientId core.ClientId, proof []byte) core.ConnectionId {
	connectionId := core.ConnectionOpenInit(cross(cur), core.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: core.ClientId(99),
	})
	core.ConnectionOpenAck(cross(cur), core.MsgConnectionOpenAck{
		ConnectionId:             connectionId,
		CounterpartyConnectionId: core.ConnectionId(77),
		ProofTry:                 proof,
		ProofHeight:              core.Height(realcometbls.DevnetHeight - 1),
	})
	return connectionId
}

// Error:
// zkgm: unsupported channel version
