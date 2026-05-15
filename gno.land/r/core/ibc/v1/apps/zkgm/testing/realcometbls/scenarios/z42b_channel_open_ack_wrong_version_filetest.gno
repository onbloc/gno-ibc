package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	clientId := realcometbls.CreateZ42WrongVersionCometBLSClient(cross)
	connectionId := openConnection(clientId, realcometbls.Z42WrongVersionConnectionTryProof(cross))
	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             []byte(zkgm.ProxyPkgPath()),
		CounterpartyPortId: []byte(zkgm.ProxyPkgPath()),
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})

	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   "bad-version",
		CounterpartyChannelId: core.ChannelId(2),
		ProofTry:              realcometbls.Z42WrongVersionChannelTryProof(cross),
		ProofHeight:           core.Height(realcometbls.DevnetHeight - 1),
	})
}

func openConnection(clientId core.ClientId, proof []byte) core.ConnectionId {
	connectionId := core.ConnectionOpenInit(cross, core.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: core.ClientId(99),
	})
	core.ConnectionOpenAck(cross, core.MsgConnectionOpenAck{
		ConnectionId:             connectionId,
		CounterpartyConnectionId: core.ConnectionId(77),
		ProofTry:                 proof,
		ProofHeight:              core.Height(realcometbls.DevnetHeight - 1),
	})
	return connectionId
}

// Error:
// zkgm: unsupported channel version
