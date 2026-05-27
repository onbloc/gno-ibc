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
	channelId := core.ChannelOpenInit(cross(cur), core.MsgChannelOpenInit{
		PortId:             []byte(zkgm.ProxyPkgPath()),
		CounterpartyPortId: []byte(zkgm.ProxyPkgPath()),
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})

	core.ChannelOpenAck(cross(cur), core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: core.ChannelId(3),
		ProofTry:              realcometbls.Z35ChannelTryProof(cross(cur)),
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
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
