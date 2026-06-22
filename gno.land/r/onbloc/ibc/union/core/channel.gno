package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

func ChannelOpenInit(cur realm, msg types.MsgChannelOpenInit) types.ChannelId {
	requireCanCall(0, cur, SelectorChannelOpenInit)

	relayer := cur.Previous().Address()
	portId := types.Bytes(cloneBytes(msg.PortId))
	ensureConnectionOpen(msg.ConnectionId)
	channelId := store.nextChannelId()

	channel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    types.Bytes(cloneBytes(msg.CounterpartyPortId)),
		Version:               msg.Version,
	}
	store.createChannel(channelId, channel, portId)

	store.getAppByPortId(portId).OnChannelOpenInit(cross(cur), msg.ConnectionId, channelId, msg.Version, relayer)
	emitChannelOpenInitEvent(portId, channelId, channel)
	return channelId
}

func ChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) types.ChannelId {
	requireCanCall(0, cur, SelectorChannelOpenTry)
	return channelOpenTry(cur, msg, true)
}

func ForceChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) types.ChannelId {
	requireCanCall(0, cur, SelectorForceChannelTry)
	return channelOpenTry(cur, msg, false)
}

func channelOpenTry(cur realm, msg types.MsgChannelOpenTry, verify bool) types.ChannelId {
	relayer := cur.Previous().Address()
	portId := types.Bytes(cloneBytes(msg.PortId))
	if msg.Channel.State != types.ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	if msg.Channel.CounterpartyChannelId == 0 {
		panic(ErrInvalidCounterpartyChannelId)
	}
	connection := ensureConnectionOpen(msg.Channel.ConnectionId)
	channelId := store.nextChannelId()

	if verify {
		expectedChannel := types.Channel{
			State:                 types.ChannelStateInit,
			ConnectionId:          connection.CounterpartyConnectionId,
			CounterpartyChannelId: 0,
			CounterpartyPortId:    portId,
			Version:               msg.CounterpartyVersion,
		}
		key := types.ChannelPath(msg.Channel.CounterpartyChannelId)
		value := channelValue(expectedChannel)
		verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])
	}

	store.createChannel(channelId, msg.Channel, portId)

	store.getAppByPortId(portId).OnChannelOpenTry(cross(cur), msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, relayer)
	emitChannelOpenTryEvent(portId, channelId, msg.Channel, msg.CounterpartyVersion)
	return channelId
}

func ChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	requireCanCall(0, cur, SelectorChannelOpenAck)
	channelOpenAck(cur, msg, true)
}

func ForceChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	requireCanCall(0, cur, SelectorForceChannelAck)
	channelOpenAck(cur, msg, false)
}

func channelOpenAck(cur realm, msg types.MsgChannelOpenAck, verify bool) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateInit {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := store.getChannelOwner(msg.ChannelId)

	if verify {
		expectedChannel := types.Channel{
			State:                 types.ChannelStateTryOpen,
			ConnectionId:          connection.CounterpartyConnectionId,
			CounterpartyChannelId: msg.ChannelId,
			CounterpartyPortId:    portId,
			Version:               msg.CounterpartyVersion,
		}
		key := types.ChannelPath(msg.CounterpartyChannelId)
		value := channelValue(expectedChannel)
		verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofTry, key[:], value[:])
	}

	channel.State = types.ChannelStateOpen
	channel.Version = msg.CounterpartyVersion
	channel.CounterpartyChannelId = msg.CounterpartyChannelId
	store.saveChannel(msg.ChannelId, channel)

	store.getAppByPortId(portId).OnChannelOpenAck(cross(cur), msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, relayer)
	emitChannelOpenAckEvent(portId, msg.ChannelId, channel)
}

func ChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	requireCanCall(0, cur, SelectorChannelOpenConfirm)
	channelOpenConfirm(cur, msg, true)
}

func ForceChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	requireCanCall(0, cur, SelectorForceChannelConfirm)
	channelOpenConfirm(cur, msg, false)
}

func channelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm, verify bool) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	if channel.CounterpartyChannelId == 0 {
		panic(ErrInvalidCounterpartyChannelId)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := store.getChannelOwner(msg.ChannelId)

	if verify {
		expectedChannel := types.Channel{
			State:                 types.ChannelStateOpen,
			ConnectionId:          connection.CounterpartyConnectionId,
			CounterpartyChannelId: msg.ChannelId,
			CounterpartyPortId:    portId,
			Version:               channel.Version,
		}
		key := types.ChannelPath(channel.CounterpartyChannelId)
		value := channelValue(expectedChannel)
		verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofAck, key[:], value[:])
	}

	channel.State = types.ChannelStateOpen
	store.saveChannel(msg.ChannelId, channel)

	store.getAppByPortId(portId).OnChannelOpenConfirm(cross(cur), msg.ChannelId, relayer)
	emitChannelOpenConfirmEvent(portId, msg.ChannelId, channel)
}

func ChannelCloseInit(cur realm, msg types.MsgChannelCloseInit) {
	requireCanCall(0, cur, SelectorChannelCloseInit)

	channelCloseInit(cur, msg)
}

func channelCloseInit(cur realm, msg types.MsgChannelCloseInit) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	if channel.CounterpartyChannelId == 0 {
		panic(ErrInvalidCounterpartyChannelId)
	}
	ensureConnectionOpen(channel.ConnectionId)
	portId := store.getChannelOwner(msg.ChannelId)

	channel.State = types.ChannelStateClosed
	store.saveChannel(msg.ChannelId, channel)

	store.getAppByPortId(portId).OnChannelCloseInit(cross(cur), msg.ChannelId, relayer)
	emitChannelCloseInitEvent(portId, msg.ChannelId, channel)
}

func ChannelCloseConfirm(cur realm, msg types.MsgChannelCloseConfirm) {
	requireCanCall(0, cur, SelectorChannelCloseConfirm)

	channelCloseConfirm(cur, msg)
}

func channelCloseConfirm(cur realm, msg types.MsgChannelCloseConfirm) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	if channel.CounterpartyChannelId == 0 {
		panic(ErrInvalidCounterpartyChannelId)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := store.getChannelOwner(msg.ChannelId)

	expectedChannel := types.Channel{
		State:                 types.ChannelStateClosed,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               channel.Version,
	}
	key := types.ChannelPath(channel.CounterpartyChannelId)
	value := channelValue(expectedChannel)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])

	channel.State = types.ChannelStateClosed
	store.saveChannel(msg.ChannelId, channel)

	store.getAppByPortId(portId).OnChannelCloseConfirm(cross(cur), msg.ChannelId, relayer)
	emitChannelCloseConfirmEvent(portId, msg.ChannelId, channel)
}

func QueryChannel(channelId types.ChannelId) string {
	entry, found := store.getChannelEntry(channelId)
	if !found {
		return ""
	}
	bz, err := entry.channel.EncodeABI()
	if err != nil {
		return ""
	}
	return hexString(bz)
}

// GetChannel returns the stored channel record for channelId. Apps need this
// to look up the counterparty channel id when constructing packets to send via
// BatchSend (the core no longer auto-derives it from a sender-side helper).
func GetChannel(channelId types.ChannelId) types.Channel {
	return store.getChannel(channelId)
}
