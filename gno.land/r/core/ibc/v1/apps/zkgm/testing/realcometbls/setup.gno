package realcometbls

import (
	core "gno.land/r/core/ibc/v1/core"
	realcometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
	zkgm "gno.land/r/onbloc/ibc/v1/apps/zkgm"
)

type ChannelPair struct {
	ClientId     core.ClientId
	ConnectionId core.ConnectionId
	Source       core.ChannelId
	Destination  core.ChannelId
}

func CreateRealCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), TrustedConsensusStateBytes(cross(cur)))
}

func CreateSyntheticCometBLSClient(cur realm) core.ClientId {
	return createSyntheticCometBLSClient(cross(cur), ClientStateBytes(cross(cur)))
}

func CreateFrozenSyntheticCometBLSClient(cur realm) core.ClientId {
	return createSyntheticCometBLSClient(cross(cur), FrozenClientStateBytes(cross(cur)))
}

func CreateExpiredSyntheticCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross(cur), ExpiredClientStateBytes(cross(cur)), ExpiredSyntheticConsensusStateBytes(cross(cur)))
}

func CreateZ35CometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z35ConsensusStateBytes(cross(cur)))
}

func CreateZ37CometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z37ConsensusStateBytes(cross(cur)))
}

func CreateZ42WrongVersionCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z42WrongVersionConsensusStateBytes(cross(cur)))
}

func CreateZ42StaleCometBLSClient(cur realm) core.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z42StaleConsensusStateBytes(cross(cur)))
}

func createSyntheticCometBLSClient(cur realm, clientStateBytes []byte) core.ClientId {
	return createCometBLSClient(cross(cur), clientStateBytes, SyntheticConsensusStateBytes(cross(cur)))
}

func createCometBLSClient(cur realm, clientStateBytes, consensusStateBytes []byte) core.ClientId {
	if !core.HasClient(realcometbls.ClientType) {
		realcometbls.Register(cross(cur))
	}
	return core.CreateClient(cross(cur), core.NewMsgCreateClient(cross(cur), realcometbls.ClientType, clientStateBytes, consensusStateBytes))
}

func OpenZ35CometBLSChannel(cur realm) ChannelPair {
	clientId := CreateZ35CometBLSClient(cross(cur))

	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), Z35ConnectionTryProof(cross(cur)), core.Height(DevnetHeight-1)))

	destination := openZ35Channel(cross(cur), connectionId, core.ChannelId(2))
	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       core.ChannelId(2),
		Destination:  destination,
	}
}

func openZ35Channel(cur realm, connectionId core.ConnectionId, counterpartyChannelId core.ChannelId) core.ChannelId {
	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), channelId, zkgm.Version, counterpartyChannelId, Z35ChannelTryProof(cross(cur)), core.Height(DevnetHeight-1)))
	return channelId
}

func BatchSend(cur realm, packet core.Packet) core.H256 {
	return zkgm.BatchSend(cross(cur), core.NewMsgBatchSend(cross(cur), []core.Packet{packet}))
}

func OpenZ37CometBLSChannel(cur realm) ChannelPair {
	clientId := CreateZ37CometBLSClient(cross(cur))

	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), Z37ConnectionTryProof(cross(cur)), core.Height(DevnetHeight-1)))

	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), channelId, zkgm.Version, core.ChannelId(2), Z37ChannelTryProof(cross(cur)), core.Height(DevnetHeight-1)))
	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       core.ChannelId(2),
		Destination:  channelId,
	}
}

func UpdateRealCometBLSClient(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross(cur), core.NewMsgUpdateClient(cross(cur), clientId, HeaderBytes(cross(cur))))
}

func UpdateRealCometBLSClientWithTamperedHeader(cur realm, clientId core.ClientId) core.Height {
	return core.UpdateClient(cross(cur), core.NewMsgUpdateClient(cross(cur), clientId, TamperedHeaderBytes(cross(cur))))
}
