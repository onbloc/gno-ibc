package realcometbls

import (
	stdtesting "testing"

	types "gno.land/p/onbloc/ibc/union/types"

	realcometbls "gno.land/p/onbloc/ibc/union/lightclient/cometbls"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

type ChannelPair struct {
	ClientId     types.ClientId
	ConnectionId types.ConnectionId
	Source       types.ChannelId
	Destination  types.ChannelId
}

var testClientSeq uint32
var testConnectionSeq uint32

func nextTestClientId() types.ClientId {
	testClientSeq++
	return types.ClientId(testClientSeq)
}

func nextTestConnectionId() types.ConnectionId {
	testConnectionSeq++
	return types.ConnectionId(testConnectionSeq)
}

func CreateRealCometBLSClient(cur realm) types.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), TrustedConsensusStateBytes(cross(cur)))
}

func CreateSyntheticCometBLSClient(cur realm) types.ClientId {
	return createSyntheticCometBLSClient(cross(cur), ClientStateBytes(cross(cur)))
}

func CreateFrozenSyntheticCometBLSClient(cur realm) types.ClientId {
	return createSyntheticCometBLSClient(cross(cur), FrozenClientStateBytes(cross(cur)))
}

func CreateExpiredSyntheticCometBLSClient(cur realm) types.ClientId {
	return createCometBLSClient(cross(cur), ExpiredClientStateBytes(cross(cur)), ExpiredSyntheticConsensusStateBytes(cross(cur)))
}

func CreateZ35CometBLSClient(cur realm) types.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z35ConsensusStateBytes(cross(cur)))
}

func CreateZ37CometBLSClient(cur realm) types.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z37ConsensusStateBytes(cross(cur)))
}

func CreateZ42WrongVersionCometBLSClient(cur realm) types.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z42WrongVersionConsensusStateBytes(cross(cur)))
}

func CreateZ42StaleCometBLSClient(cur realm) types.ClientId {
	return createCometBLSClient(cross(cur), ClientStateBytes(cross(cur)), Z42StaleConsensusStateBytes(cross(cur)))
}

func createSyntheticCometBLSClient(cur realm, clientStateBytes []byte) types.ClientId {
	return createCometBLSClient(cross(cur), clientStateBytes, SyntheticConsensusStateBytes(cross(cur)))
}

func createCometBLSClient(cur realm, clientStateBytes, consensusStateBytes []byte) types.ClientId {
	clientState, err := realcometbls.DecodeClientState(clientStateBytes)
	if err != nil {
		panic(err)
	}

	consensusState, err := realcometbls.DecodeConsensusState(consensusStateBytes)
	if err != nil {
		panic(err)
	}

	lightClient, err := realcometbls.NewCometblsLightClient(clientState, consensusState)
	if err != nil {
		panic(err)
	}

	clientType := types.ClientType(realcometbls.ClientType)
	if !core.HasClient(clientType) {
		core.RegisterClient(cross(cur), clientType, lightClient)
	}

	clientId := nextTestClientId()

	core.CreateClient(cross(cur), types.NewMsgCreateClient(clientType, clientStateBytes, consensusStateBytes))

	return clientId
}

func OpenZ35CometBLSChannel(cur realm) ChannelPair {
	clientId := CreateZ35CometBLSClient(cross(cur))

	connectionId := nextTestConnectionId()

	core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), Z35ConnectionTryProof(cross(cur)), uint64(DevnetHeight-1)))

	destination := openZ35Channel(cross(cur), connectionId, types.ChannelId(2))

	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       types.ChannelId(2),
		Destination:  destination,
	}
}

func openZ35Channel(cur realm, connectionId types.ConnectionId, counterpartyChannelId types.ChannelId) types.ChannelId {
	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1msgrelayer"))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, zkgm.Version, counterpartyChannelId, Z35ChannelTryProof(cross(cur)), uint64(DevnetHeight-1), "g1msgrelayer"))

	return channelId
}

func BatchSend(cur realm, packet types.Packet) types.H256 {
	stdtesting.SetRealm(stdtesting.NewCodeRealm(zkgm.ProductionImplPath()))
	core.BatchSend(cross(cur), types.NewMsgBatchSend([]types.Packet{packet}))
	stdtesting.SetRealm(stdtesting.NewCodeRealm("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"))

	return types.MustCommit(types.CommitPackets([]types.Packet{packet}))
}

func OpenZ37CometBLSChannel(cur realm) ChannelPair {
	clientId := CreateZ37CometBLSClient(cross(cur))

	connectionId := nextTestConnectionId()

	core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), Z37ConnectionTryProof(cross(cur)), uint64(DevnetHeight-1)))

	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1msgrelayer"))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), Z37ChannelTryProof(cross(cur)), uint64(DevnetHeight-1), "g1msgrelayer"))

	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       types.ChannelId(2),
		Destination:  channelId,
	}
}

func UpdateRealCometBLSClient(cur realm, clientId types.ClientId) types.Height {
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, HeaderBytes(cross(cur))))
	height, _ := core.GetLatestHeight(clientId)
	return types.NewHeight(height)
}

func UpdateRealCometBLSClientWithTamperedHeader(cur realm, clientId types.ClientId) types.Height {
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, TamperedHeaderBytes(cross(cur))))
	height, _ := core.GetLatestHeight(clientId)
	return types.NewHeight(height)
}
