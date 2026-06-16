package core

import "gno.land/p/onbloc/ibc/union/types"

func ChannelOpenInit(cur realm, msg types.MsgChannelOpenInit) types.ChannelId {
	relayer := cur.Previous().Address()
	portId := types.Bytes(cloneBytes(msg.PortId))
	connection := ensureConnectionOpen(msg.ConnectionId)
	channelId := st.generateChannelId()
	st.channelOwners[channelId] = portId

	st.getAppByPortId(portId).OnChannelOpenInit(cross(cur), msg.ConnectionId, channelId, msg.Version, relayer)

	channel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    types.Bytes(cloneBytes(msg.CounterpartyPortId)),
		Version:               msg.Version,
	}
	st.saveChannel(channelId, channel)
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
	channelId := st.generateChannelId()

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

	st.channelOwners[channelId] = portId
	st.getAppByPortId(portId).OnChannelOpenTry(cross(cur), msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, relayer)
	st.saveChannel(channelId, msg.Channel)

	emitChannelEvent(ChannelOpenTryEvent, portId, channelId, msg.Channel, connection)
	return channelId
}

func ChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	relayer := cur.Previous().Address()
	channel := st.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateInit {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)

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

	st.getAppByPortId(portId).OnChannelOpenAck(cross(cur), msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, relayer)

	channel.State = types.ChannelStateOpen
	channel.Version = msg.CounterpartyVersion
	channel.CounterpartyChannelId = msg.CounterpartyChannelId
	st.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenAckEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	relayer := cur.Previous().Address()
	channel := st.getChannel(msg.ChannelId)
	if channel.State != types.ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)

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

	st.getAppByPortId(portId).OnChannelOpenConfirm(cross(cur), msg.ChannelId, relayer)
	channel.State = types.ChannelStateOpen
	st.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenConfirmEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelCloseInit(cur realm, msg types.MsgChannelCloseInit) {
	panic("channel close init unsupported: Union types.MsgChannelCloseInit has no channel id")
}

func ChannelCloseConfirm(cur realm, msg types.MsgChannelCloseConfirm) {
	panic("channel close confirm unsupported: Union types.MsgChannelCloseConfirm has no channel id")
}

func QueryChannel(channelId types.ChannelId) string {
	channel, ok := st.channels[channelId]
	if !ok {
		return ""
	}
	bz, err := channel.EncodeABI()
	if err != nil {
		return ""
	}
	return hexString(bz)
}

// GetChannel returns the stored channel record for channelId. Apps need this
// to look up the counterparty channel id when constructing packets to send via
// BatchSend (the core no longer auto-derives it from a sender-side helper).
func GetChannel(channelId types.ChannelId) types.Channel {
	return st.getChannel(channelId)
}
