package realcometbls

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

type ChannelPair struct {
	ClientId     core.ClientId
	ConnectionId core.ConnectionId
	Source       core.ChannelId
	Destination  core.ChannelId
}

func CreateRealCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross, ClientStateBytes(cross), TrustedConsensusStateBytes(cross))
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

func CreateZ37CometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross, ClientStateBytes(cross), Z37ConsensusStateBytes(cross))
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
	if !core.HasClient(realcometbls.ClientType) {
		core.RegisterClient(cross, realcometbls.ClientType, realcometbls.Adapter{})
	}
	return core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          realcometbls.ClientType,
		ClientStateBytes:    clientStateBytes,
		ConsensusStateBytes: consensusStateBytes,
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
		ProofTry:                 Z35ConnectionTryProof(cross),
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
	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             portId,
		CounterpartyPortId: portId,
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})
	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: counterpartyChannelId,
		ProofTry:              Z35ChannelTryProof(cross),
		ProofHeight:           core.Height(DevnetHeight - 1),
	})
	return channelId
}

func BatchSend(cur realm, packet core.Packet) core.H256 {
	return zkgm.BatchSend(cross, core.MsgBatchSend{Packets: []core.Packet{packet}})
}

func OpenZ37CometBLSChannel(cur realm) ChannelPair {
	clientId := CreateZ37CometBLSClient(cross)

	connectionId := core.ConnectionOpenInit(cross, core.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: core.ClientId(99),
	})
	core.ConnectionOpenAck(cross, core.MsgConnectionOpenAck{
		ConnectionId:             connectionId,
		CounterpartyConnectionId: core.ConnectionId(77),
		ProofTry:                 Z37ConnectionTryProof(cross),
		ProofHeight:              core.Height(DevnetHeight - 1),
	})

	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             portId,
		CounterpartyPortId: portId,
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})
	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: core.ChannelId(2),
		ProofTry:              Z37ChannelTryProof(cross),
		ProofHeight:           core.Height(DevnetHeight - 1),
	})
	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       core.ChannelId(2),
		Destination:  channelId,
	}
}

func UpdateRealCometBLSClient(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: HeaderBytes(cross),
	})
}

func UpdateRealCometBLSClientWithTamperedHeader(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: TamperedHeaderBytes(cross),
	})
}
