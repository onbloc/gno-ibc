package impl

import (
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// channel.gno: channel handshake and close logic. The admin gate stays on the
// proxy entrypoint; the Force* recovery variants remain proxy admin operations.
// Each handshake step dispatches the matching callback to the channel's app.

// ChannelOpenInit starts a channel in the Init state and notifies its app.
func (c *coreV1) ChannelOpenInit(_ int, rlm realm, msg types.MsgChannelOpenInit) types.ChannelId {
	relayer := rlm.Previous().Address()
	portId := types.Bytes(cloneBytes(msg.PortId))
	c.ensureConnectionOpen(msg.ConnectionId)
	channelId := c.store.NextChannelId(0, rlm)

	channel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          msg.ConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    types.Bytes(cloneBytes(msg.CounterpartyPortId)),
		Version:               msg.Version,
	}
	c.store.CreateChannel(0, rlm, channelId, channel, portId)

	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic("port " + string(portId) + " not found")
	}
	a.OnChannelOpenInit(cross(rlm), msg.ConnectionId, channelId, msg.Version, relayer)
	core.EmitChannelOpenInit(portId, channelId, channel)
	return channelId
}

// ChannelOpenTry proves a counterparty Init and opens the local channel in
// TryOpen, notifying its app.
func (c *coreV1) ChannelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry) types.ChannelId {
	relayer := rlm.Previous().Address()
	portId := types.Bytes(cloneBytes(msg.PortId))
	if msg.Channel.State != types.ChannelStateTryOpen {
		panic(core.ErrInvalidChannelState)
	}
	if msg.Channel.CounterpartyChannelId == 0 {
		panic(core.ErrInvalidCounterpartyChannelId)
	}
	connection := c.ensureConnectionOpen(msg.Channel.ConnectionId)
	channelId := c.store.NextChannelId(0, rlm)

	expectedChannel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: 0,
		CounterpartyPortId:    portId,
		Version:               msg.CounterpartyVersion,
	}
	key := types.ChannelPath(msg.Channel.CounterpartyChannelId)
	value := core.ChannelValue(expectedChannel)
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])

	c.store.CreateChannel(0, rlm, channelId, msg.Channel, portId)

	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic("port " + string(portId) + " not found")
	}
	a.OnChannelOpenTry(cross(rlm), msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, relayer)
	core.EmitChannelOpenTry(portId, channelId, msg.Channel, msg.CounterpartyVersion)
	return channelId
}

// ChannelOpenAck proves the counterparty TryOpen and moves the local Init
// channel to Open, notifying its app.
func (c *coreV1) ChannelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck) {
	relayer := rlm.Previous().Address()
	channel, ok := c.store.GetChannel(msg.ChannelId)
	if !ok {
		panic("channel " + msg.ChannelId.String() + " not found")
	}
	if channel.State != types.ChannelStateInit {
		panic(core.ErrInvalidChannelState)
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)
	portId, _ := c.store.GetChannelOwner(msg.ChannelId)

	expectedChannel := types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               msg.CounterpartyVersion,
	}
	key := types.ChannelPath(msg.CounterpartyChannelId)
	value := core.ChannelValue(expectedChannel)
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofTry, key[:], value[:])

	updated := types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          channel.ConnectionId,
		CounterpartyChannelId: msg.CounterpartyChannelId,
		CounterpartyPortId:    types.Bytes(cloneBytes(channel.CounterpartyPortId)),
		Version:               msg.CounterpartyVersion,
	}
	c.store.SaveChannel(0, rlm, msg.ChannelId, updated)

	a, _ := c.store.GetAppByPortId(portId)
	a.OnChannelOpenAck(cross(rlm), msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, relayer)
	core.EmitChannelOpenAck(portId, msg.ChannelId, updated)
}

// ChannelOpenConfirm proves the counterparty Open and moves the local TryOpen
// channel to Open, notifying its app.
func (c *coreV1) ChannelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm) {
	relayer := rlm.Previous().Address()
	channel, ok := c.store.GetChannel(msg.ChannelId)
	if !ok {
		panic("channel " + msg.ChannelId.String() + " not found")
	}
	if channel.State != types.ChannelStateTryOpen {
		panic(core.ErrInvalidChannelState)
	}
	if channel.CounterpartyChannelId == 0 {
		panic(core.ErrInvalidCounterpartyChannelId)
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)
	portId, _ := c.store.GetChannelOwner(msg.ChannelId)

	expectedChannel := types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               channel.Version,
	}
	key := types.ChannelPath(channel.CounterpartyChannelId)
	value := core.ChannelValue(expectedChannel)
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofAck, key[:], value[:])

	updated := types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          channel.ConnectionId,
		CounterpartyChannelId: channel.CounterpartyChannelId,
		CounterpartyPortId:    types.Bytes(cloneBytes(channel.CounterpartyPortId)),
		Version:               channel.Version,
	}
	c.store.SaveChannel(0, rlm, msg.ChannelId, updated)

	a, _ := c.store.GetAppByPortId(portId)
	a.OnChannelOpenConfirm(cross(rlm), msg.ChannelId, relayer)
	core.EmitChannelOpenConfirm(portId, msg.ChannelId, updated)
}

// ChannelCloseInit closes an Open channel locally and notifies its app.
func (c *coreV1) ChannelCloseInit(_ int, rlm realm, msg types.MsgChannelCloseInit) {
	relayer := rlm.Previous().Address()
	channel, ok := c.store.GetChannel(msg.ChannelId)
	if !ok {
		panic("channel " + msg.ChannelId.String() + " not found")
	}
	if channel.State != types.ChannelStateOpen {
		panic(core.ErrInvalidChannelState)
	}
	if channel.CounterpartyChannelId == 0 {
		panic(core.ErrInvalidCounterpartyChannelId)
	}
	c.ensureConnectionOpen(channel.ConnectionId)
	portId, _ := c.store.GetChannelOwner(msg.ChannelId)

	updated := c.closedChannel(channel)
	c.store.SaveChannel(0, rlm, msg.ChannelId, updated)

	a, _ := c.store.GetAppByPortId(portId)
	a.OnChannelCloseInit(cross(rlm), msg.ChannelId, relayer)
	core.EmitChannelCloseInit(portId, msg.ChannelId, updated)
}

// ChannelCloseConfirm proves the counterparty Closed and closes the local
// channel, notifying its app.
func (c *coreV1) ChannelCloseConfirm(_ int, rlm realm, msg types.MsgChannelCloseConfirm) {
	relayer := rlm.Previous().Address()
	channel, ok := c.store.GetChannel(msg.ChannelId)
	if !ok {
		panic("channel " + msg.ChannelId.String() + " not found")
	}
	if channel.State != types.ChannelStateOpen {
		panic(core.ErrInvalidChannelState)
	}
	if channel.CounterpartyChannelId == 0 {
		panic(core.ErrInvalidCounterpartyChannelId)
	}
	connection := c.ensureConnectionOpen(channel.ConnectionId)
	portId, _ := c.store.GetChannelOwner(msg.ChannelId)

	expectedChannel := types.Channel{
		State:                 types.ChannelStateClosed,
		ConnectionId:          connection.CounterpartyConnectionId,
		CounterpartyChannelId: msg.ChannelId,
		CounterpartyPortId:    portId,
		Version:               channel.Version,
	}
	key := types.ChannelPath(channel.CounterpartyChannelId)
	value := core.ChannelValue(expectedChannel)
	c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])

	updated := c.closedChannel(channel)
	c.store.SaveChannel(0, rlm, msg.ChannelId, updated)

	a, _ := c.store.GetAppByPortId(portId)
	a.OnChannelCloseConfirm(cross(rlm), msg.ChannelId, relayer)
	core.EmitChannelCloseConfirm(portId, msg.ChannelId, updated)
}

// closedChannel returns a Closed copy of channel without mutating the store-owned
// value.
func (c *coreV1) closedChannel(channel types.Channel) types.Channel {
	return types.Channel{
		State:                 types.ChannelStateClosed,
		ConnectionId:          channel.ConnectionId,
		CounterpartyChannelId: channel.CounterpartyChannelId,
		CounterpartyPortId:    types.Bytes(cloneBytes(channel.CounterpartyPortId)),
		Version:               channel.Version,
	}
}
