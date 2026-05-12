package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	clientId := realcometbls.CreateZ35CometBLSClient(cross)
	connectionId := openConnection(clientId, realcometbls.Z35ConnectionTryProof(cross))
	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             zkgm.ProxyAddress(),
		CounterpartyPortId: zkgm.ProxyAddress(),
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
		Relayer:            realcometbls.Relayer,
	})

	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: core.ChannelId(3),
		ProofTry:              core.NewBytes(cross, realcometbls.Z35ChannelTryProof(cross)),
		ProofHeight:           core.Height(realcometbls.DevnetHeight - 1),
		Relayer:               realcometbls.Relayer,
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
		ProofTry:                 core.NewBytes(cross, proof),
		ProofHeight:              core.Height(realcometbls.DevnetHeight - 1),
	})
	return connectionId
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
