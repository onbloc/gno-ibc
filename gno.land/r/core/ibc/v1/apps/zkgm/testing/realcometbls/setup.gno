package realcometbls

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
)

func CreateRealCometBLSClient(cur realm) core.ClientId {
	return core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          realcometbls.ClientType,
		ClientStateBytes:    core.NewBytes(cross, ClientStateBytes(cross)),
		ConsensusStateBytes: core.NewBytes(cross, TrustedConsensusStateBytes(cross)),
		Relayer:             address("g1relayer"),
	})
}

func UpdateRealCometBLSClient(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: core.NewBytes(cross, HeaderBytes(cross)),
		Relayer:       address("g1relayer"),
	})
}

func UpdateRealCometBLSClientWithTamperedHeader(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: core.NewBytes(cross, TamperedHeaderBytes(cross)),
		Relayer:       address("g1relayer"),
	})
}
