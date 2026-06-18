package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

func ChannelOpenInit(cur realm, msg types.MsgChannelOpenInit) types.ChannelId {
	relayer := cur.Previous().Address()
	portId := types.Bytes(cloneBytes(msg.PortId))
	connection := ensureConnectionOpen(msg.ConnectionId)
	channelId := store.nextChannelId()

	store.getAppByPortId(portId).OnChannelOpenInit(cross(cur), msg.ConnectionId, channelId, msg.Version, relayer)

	channel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    types.Bytes(cloneBytes(msg.CounterpartyPortId)),
		Version:               msg.Version,
	}
	store.createChannel(channelId, channel, portId)
	emitChannelEvent(ChannelOpenInitEvent, portId, channelId, channel, connection)
	return channelId
}

func ChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) types.ChannelId {
	relayer := cur.Previous().Address()
	portId := types.Bytes(cloneBytes(msg.PortId))
	if msg.Channel.State != types.ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(msg.Channel.ConnectionId)
	channelId := store.nextChannelId()

	expectedChannel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    msg.PortId,
		Version:               msg.CounterpartyVersion,
	}
	key := types.ChannelPath(msg.Channel.CounterpartyChannelId)
	value := channelValue(expectedChannel)
	verifyMembershipActive(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])

	store.getAppByPortId(portId).OnChannelOpenTry(cross(cur), msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, relayer)
	store.createChannel(channelId, msg.Channel, portId)

	emitChannelEvent(ChannelOpenTryEvent, portId, channelId, msg.Channel, connection)
	return channelId
}

func ChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateInit {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := store.getChannelOwner(msg.ChannelId)

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

	store.getAppByPortId(portId).OnChannelOpenAck(cross(cur), msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, relayer)

	channel.State = types.ChannelStateOpen
	channel.Version = msg.CounterpartyVersion
	channel.CounterpartyChannelId = msg.CounterpartyChannelId
	store.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenAckEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := store.getChannelOwner(msg.ChannelId)

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

	store.getAppByPortId(portId).OnChannelOpenConfirm(cross(cur), msg.ChannelId, relayer)
	channel.State = types.ChannelStateOpen
	store.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenConfirmEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelCloseInit(cur realm, msg types.MsgChannelCloseInit) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := store.getChannelOwner(msg.ChannelId)

	store.getAppByPortId(portId).OnChannelCloseInit(cross(cur), msg.ChannelId, relayer)

	channel.State = types.ChannelStateClosed
	store.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelCloseInitEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelCloseConfirm(cur realm, msg types.MsgChannelCloseConfirm) {
	relayer := cur.Previous().Address()
	channel := store.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateOpen {
		panic(ErrInvalidChannelState)
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
	emitChannelEvent(ChannelCloseConfirmEvent, portId, msg.ChannelId, channel, connection)
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
