package core

import rtunsafe "chain/runtime/unsafe"

func ChannelOpenInit(cur realm, msg MsgChannelOpenInit) ChannelId {
	relayer := rtunsafe.OriginCaller()
	portId := Bytes(cloneBytes(msg.PortId))
	connection := ensureConnectionOpen(msg.ConnectionId)
	channelId := st.generateChannelId()
	st.channelOwners[channelId] = portId

	st.getAppByPortId(portId).OnChannelOpenInit(cur, msg.ConnectionId, channelId, msg.Version, relayer)

	channel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    Bytes(cloneBytes(msg.CounterpartyPortId)),
		Version:               msg.Version,
	}
	st.saveChannel(channelId, channel)
	emitChannelEvent(ChannelOpenInitEvent, portId, channelId, channel, connection)
	return channelId
}

func ChannelOpenTry(cur realm, msg MsgChannelOpenTry) ChannelId {
	relayer := rtunsafe.OriginCaller()
	portId := Bytes(cloneBytes(msg.PortId))
	if msg.Channel.State != ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(msg.Channel.ConnectionId)
	channelId := st.generateChannelId()

	expectedChannel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    msg.PortId,
		Version:               msg.CounterpartyVersion,
	}
	key := ChannelPath(msg.Channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofInit, key[:], value[:])

	st.channelOwners[channelId] = portId
	st.getAppByPortId(portId).OnChannelOpenTry(cur, msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, relayer)
	st.saveChannel(channelId, msg.Channel)

	emitChannelEvent(ChannelOpenTryEvent, portId, channelId, msg.Channel, connection)
	return channelId
}

func ChannelOpenAck(cur realm, msg MsgChannelOpenAck) {
	relayer := rtunsafe.OriginCaller()
	channel := st.getChannel(msg.ChannelId)
	if channel.State != ChannelStateInit {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)

	expectedChannel := Channel{
		State:                 ChannelStateTryOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               msg.CounterpartyVersion,
	}
	key := ChannelPath(msg.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofTry, key[:], value[:])

	st.getAppByPortId(portId).OnChannelOpenAck(cur, msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, relayer)

	channel.State = ChannelStateOpen
	channel.Version = msg.CounterpartyVersion
	channel.CounterpartyChannelId = msg.CounterpartyChannelId
	st.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenAckEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelOpenConfirm(cur realm, msg MsgChannelOpenConfirm) {
	relayer := rtunsafe.OriginCaller()
	channel := st.getChannel(msg.ChannelId)
	if channel.State != ChannelStateTryOpen {
		panic(ErrInvalidChannelState)
	}
	connection := ensureConnectionOpen(channel.ConnectionId)
	portId := st.getChannelOwner(msg.ChannelId)

	expectedChannel := Channel{
		State:                 ChannelStateOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               channel.Version,
	}
	key := ChannelPath(channel.CounterpartyChannelId)
	value := keccak(expectedChannel.EthAbiEncode())
	st.getClient(connection.ClientId).VerifyMembership(connection.ClientId, msg.ProofHeight, msg.ProofAck, key[:], value[:])

	st.getAppByPortId(portId).OnChannelOpenConfirm(cur, msg.ChannelId, relayer)
	channel.State = ChannelStateOpen
	st.saveChannel(msg.ChannelId, channel)

	emitChannelEvent(ChannelOpenConfirmEvent, portId, msg.ChannelId, channel, connection)
}

func ChannelCloseInit(cur realm, msg MsgChannelCloseInit) {
	panic("channel close init unsupported: Union MsgChannelCloseInit has no channel id")
}

func ChannelCloseConfirm(cur realm, msg MsgChannelCloseConfirm) {
	panic("channel close confirm unsupported: Union MsgChannelCloseConfirm has no channel id")
}

func QueryChannel(channelId ChannelId) string {
	channel, ok := st.channels[channelId]
	if !ok {
		return ""
	}
	return hexString(channel.EthAbiEncode())
}

// GetChannel returns the stored channel record for channelId. Apps need this
// to look up the counterparty channel id when constructing packets to send via
// BatchSend (the core no longer auto-derives it from a sender-side helper).
func GetChannel(channelId ChannelId) Channel {
	return st.getChannel(channelId)
}
