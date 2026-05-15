package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	clientId := realcometbls.CreateZ42StaleCometBLSClient(cross)
	connectionId := openConnection(clientId, realcometbls.Z42StaleConnectionTryProof(cross))
	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             []byte(zkgm.ProxyPkgPath()),
		CounterpartyPortId: []byte(zkgm.ProxyPkgPath()),
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})

	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: core.ChannelId(2),
		ProofTry:              realcometbls.Z42StaleChannelTryProof(cross),
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
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided value doesn't match proof
