package main

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main() {
	clientId := realcometbls.CreateZ35CometBLSClient(cross)
	connectionId := core.ConnectionOpenInit(cross, core.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: core.ClientId(99),
	})

	core.ConnectionOpenAck(cross, core.MsgConnectionOpenAck{
		ConnectionId:             connectionId,
		CounterpartyConnectionId: core.ConnectionId(78),
		ProofTry:                 core.NewBytes(cross, realcometbls.Z35ConnectionTryProof(cross)),
		ProofHeight:              core.Height(realcometbls.DevnetHeight - 1),
	})
}

// Error:
// cometbls: membership verification failed: cometbls: membership proof verification failed: provided key doesn't match proof
