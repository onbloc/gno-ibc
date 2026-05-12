package realcometbls

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

var Relayer = address("g1relayer")

type ChannelPair struct {
	ClientId     core.ClientId
	ConnectionId core.ConnectionId
	Source       core.ChannelId
	Destination  core.ChannelId
}

func CreateRealCometBLSClient(cur realm) core.ClientId {
	return core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          realcometbls.ClientType,
		ClientStateBytes:    core.NewBytes(cross, ClientStateBytes(cross)),
		ConsensusStateBytes: core.NewBytes(cross, TrustedConsensusStateBytes(cross)),
		Relayer:             Relayer,
	})
}

func CreateSyntheticCometBLSClient(cur realm) core.ClientId {
	return createSyntheticCometBLSClient(cross, ClientStateBytes(cross))
}

func CreateFrozenSyntheticCometBLSClient(cur realm) core.ClientId {
	return createSyntheticCometBLSClient(cross, FrozenClientStateBytes(cross))
}

func CreateExpiredSyntheticCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross, ExpiredClientStateBytes(cross), ExpiredSyntheticConsensusStateBytes(cross))
}

func CreateZ35CometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross, ClientStateBytes(cross), Z35ConsensusStateBytes(cross))
}

func CreateZ42WrongVersionCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross, ClientStateBytes(cross), Z42WrongVersionConsensusStateBytes(cross))
}

func CreateZ42StaleCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross, ClientStateBytes(cross), Z42StaleConsensusStateBytes(cross))
}

func createSyntheticCometBLSClient(cur realm, clientStateBytes []byte) core.ClientId {
	return createCometBLSClient(cross, clientStateBytes, SyntheticConsensusStateBytes(cross))
}

func createCometBLSClient(cur realm, clientStateBytes, consensusStateBytes []byte) core.ClientId {
	return core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          realcometbls.ClientType,
		ClientStateBytes:    core.NewBytes(cross, clientStateBytes),
		ConsensusStateBytes: core.NewBytes(cross, consensusStateBytes),
		Relayer:             Relayer,
	})
}

func OpenZ35CometBLSChannel(cur realm) ChannelPair {
	clientId := CreateZ35CometBLSClient(cross)

	connectionId := core.ConnectionOpenInit(cross, core.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: core.ClientId(99),
	})
	core.ConnectionOpenAck(cross, core.MsgConnectionOpenAck{
		ConnectionId:             connectionId,
		CounterpartyConnectionId: core.ConnectionId(77),
		ProofTry:                 core.NewBytes(cross, Z35ConnectionTryProof(cross)),
		ProofHeight:              core.Height(DevnetHeight - 1),
	})

	destination := openZ35Channel(cross, connectionId, core.ChannelId(2))
	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       core.ChannelId(2),
		Destination:  destination,
	}
}

func openZ35Channel(cur realm, connectionId core.ConnectionId, counterpartyChannelId core.ChannelId) core.ChannelId {
	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             zkgm.ProxyAddress(),
		CounterpartyPortId: zkgm.ProxyAddress(),
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
		Relayer:            Relayer,
	})
	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: counterpartyChannelId,
		ProofTry:              core.NewBytes(cross, Z35ChannelTryProof(cross)),
		ProofHeight:           core.Height(DevnetHeight - 1),
		Relayer:               Relayer,
	})
	return channelId
}

func UpdateRealCometBLSClient(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: core.NewBytes(cross, HeaderBytes(cross)),
		Relayer:       Relayer,
	})
}

func UpdateRealCometBLSClientWithTamperedHeader(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: core.NewBytes(cross, TamperedHeaderBytes(cross)),
		Relayer:       Relayer,
	})
}
