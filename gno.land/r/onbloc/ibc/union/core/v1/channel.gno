package impl

import (
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// channel.gno: channel handshake and close logic. The admin gate stays on the
// proxy entrypoint; the Force* recovery variants remain proxy admin operations.
// Each handshake step dispatches the matching callback to the channel's app.

// ChannelOpenInit starts a channel in the Init state and notifies its app. The
// created channel id is observable through the emitted event, not returned.
func (c *coreV1) ChannelOpenInit(_ int, rlm realm, msg types.MsgChannelOpenInit) {
	relayer := rlm.Previous().Address()
	portId := types.Bytes(types.CloneBytes(msg.PortId))
	c.ensureConnectionState(msg.ConnectionId)
	channelId := c.store.NextChannelId(0, rlm)

	channel := core.NewChannel(
		types.ChannelStateInit,
		msg.ConnectionId,
		0,
		types.Bytes(types.CloneBytes(msg.CounterpartyPortId)),
		msg.Version,
	)
	c.store.CreateChannel(0, rlm, channelId, channel, portId)

	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic(makeError(core.ErrPortNotFound, string(portId)))
	}

	a.OnChannelOpenInit(cross(rlm), msg.ConnectionId, channelId, msg.Version, relayer)
	core.EmitChannelOpenInit(portId, channelId, channel)
}

// ChannelOpenTry proves a counterparty Init and opens the local channel in
// TryOpen, notifying its app.
func (c *coreV1) ChannelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry) {
	c.channelOpenTry(0, rlm, msg, true)
}

// ForceChannelOpenTry is the admin recovery variant of ChannelOpenTry that skips
// counterparty proof verification.
func (c *coreV1) ForceChannelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry) {
	c.channelOpenTry(0, rlm, msg, false)
}

func (c *coreV1) channelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry, verify bool) {
	relayer := rlm.Previous().Address()
	portId := types.Bytes(types.CloneBytes(msg.PortId))
	if msg.Channel.State != types.ChannelStateTryOpen {
		panic(makeError(core.ErrInvalidChannelState))
	}

	if msg.Channel.CounterpartyChannelId == 0 {
		panic(makeError(core.ErrInvalidCounterpartyChannelId))
	}

	connection := c.ensureConnectionState(msg.Channel.ConnectionId)
	channelId := c.store.NextChannelId(0, rlm)

	if verify {
		expectedChannel := core.NewChannel(
			types.ChannelStateInit,
			connection.CounterpartyConnectionId,
			0,
			portId,
			msg.CounterpartyVersion,
		)
		key := types.ChannelPath(msg.Channel.CounterpartyChannelId)
		value := core.ChannelValue(expectedChannel)
		c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofInit, key[:], value[:])
	}

	c.store.CreateChannel(0, rlm, channelId, msg.Channel, portId)

	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic(makeError(core.ErrPortNotFound, string(portId)))
	}

	a.OnChannelOpenTry(cross(rlm), msg.Channel.ConnectionId, channelId, msg.Channel.Version, msg.CounterpartyVersion, relayer)

	core.EmitChannelOpenTry(portId, channelId, msg.Channel, msg.CounterpartyVersion)
}

// ChannelOpenAck proves the counterparty TryOpen and moves the local Init
// channel to Open, notifying its app.
func (c *coreV1) ChannelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck) {
	c.channelOpenAck(0, rlm, msg, true)
}

// ForceChannelOpenAck is the admin recovery variant of ChannelOpenAck that skips
// counterparty proof verification.
func (c *coreV1) ForceChannelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck) {
	c.channelOpenAck(0, rlm, msg, false)
}

func (c *coreV1) channelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck, verify bool) {
	relayer := rlm.Previous().Address()

	channel, ok := c.store.GetChannel(msg.ChannelId)
	if !ok {
		panic(makeError(core.ErrChannelNotFound, msg.ChannelId.String()))
	}

	if channel.State != types.ChannelStateInit {
		panic(makeError(core.ErrInvalidChannelState))
	}

	connection := c.ensureConnectionState(channel.ConnectionId)
	portId, _ := c.store.GetChannelOwner(msg.ChannelId)

	if verify {
		expectedChannel := core.NewChannel(
			types.ChannelStateTryOpen,
			connection.CounterpartyConnectionId,
			msg.ChannelId,
			portId,
			msg.CounterpartyVersion,
		)
		key := types.ChannelPath(msg.CounterpartyChannelId)
		value := core.ChannelValue(expectedChannel)
		c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofTry, key[:], value[:])
	}

	updated := core.NewChannel(
		types.ChannelStateOpen,
		channel.ConnectionId,
		msg.CounterpartyChannelId,
		channel.CounterpartyPortId.Clone(),
		msg.CounterpartyVersion,
	)
	c.store.SaveChannel(0, rlm, msg.ChannelId, updated)

	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic(makeError(core.ErrPortNotFound, string(portId)))
	}

	a.OnChannelOpenAck(cross(rlm), msg.ChannelId, msg.CounterpartyChannelId, msg.CounterpartyVersion, relayer)

	core.EmitChannelOpenAck(portId, msg.ChannelId, updated)
}

// ChannelOpenConfirm proves the counterparty Open and moves the local TryOpen
// channel to Open, notifying its app.
func (c *coreV1) ChannelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm) {
	c.channelOpenConfirm(0, rlm, msg, true)
}

// ForceChannelOpenConfirm is the admin recovery variant of ChannelOpenConfirm
// that skips counterparty proof verification.
func (c *coreV1) ForceChannelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm) {
	c.channelOpenConfirm(0, rlm, msg, false)
}

func (c *coreV1) channelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm, verify bool) {
	relayer := rlm.Previous().Address()

	channel, ok := c.store.GetChannel(msg.ChannelId)
	if !ok {
		panic(makeError(core.ErrChannelNotFound, msg.ChannelId.String()))
	}

	if channel.State != types.ChannelStateTryOpen {
		panic(makeError(core.ErrInvalidChannelState))
	}

	if channel.CounterpartyChannelId == 0 {
		panic(makeError(core.ErrInvalidCounterpartyChannelId))
	}

	connection := c.ensureConnectionState(channel.ConnectionId)
	portId, _ := c.store.GetChannelOwner(msg.ChannelId)

	if verify {
		expectedChannel := core.NewChannel(
			types.ChannelStateOpen,
			connection.CounterpartyConnectionId,
			msg.ChannelId,
			portId,
			channel.Version,
		)
		key := types.ChannelPath(channel.CounterpartyChannelId)
		value := core.ChannelValue(expectedChannel)
		c.verifyMembership(connection.ClientId, types.NewHeight(msg.ProofHeight), msg.ProofAck, key[:], value[:])
	}

	updated := core.NewChannel(
		types.ChannelStateOpen,
		channel.ConnectionId,
		channel.CounterpartyChannelId,
		channel.CounterpartyPortId.Clone(),
		channel.Version,
	)
	c.store.SaveChannel(0, rlm, msg.ChannelId, updated)

	a, ok := c.store.GetAppByPortId(portId)
	if !ok {
		panic(makeError(core.ErrPortNotFound, string(portId)))
	}

	a.OnChannelOpenConfirm(cross(rlm), msg.ChannelId, relayer)

	core.EmitChannelOpenConfirm(portId, msg.ChannelId, updated)
}

// ChannelCloseInit closes an Open channel locally and notifies its app.
func (c *coreV1) ChannelCloseInit(_ int, rlm realm, msg types.MsgChannelCloseInit) {
	relayer := rlm.Previous().Address()

	channel, ok := c.store.GetChannel(msg.ChannelId)
	if !ok {
		panic(makeError(core.ErrChannelNotFound, msg.ChannelId.String()))
	}

	if channel.State != types.ChannelStateOpen {
		panic(makeError(core.ErrInvalidChannelState))
	}

	if channel.CounterpartyChannelId == 0 {
		panic(makeError(core.ErrInvalidCounterpartyChannelId))
	}

	c.ensureConnectionState(channel.ConnectionId)
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
		panic(makeError(core.ErrChannelNotFound, msg.ChannelId.String()))
	}

	if channel.State != types.ChannelStateOpen {
		panic(makeError(core.ErrInvalidChannelState))
	}

	if channel.CounterpartyChannelId == 0 {
		panic(makeError(core.ErrInvalidCounterpartyChannelId))
	}

	connection := c.ensureConnectionState(channel.ConnectionId)
	portId, _ := c.store.GetChannelOwner(msg.ChannelId)

	expectedChannel := core.NewChannel(
		types.ChannelStateClosed,
		connection.CounterpartyConnectionId,
		msg.ChannelId,
		portId,
		channel.Version,
	)
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
	return core.NewChannel(
		types.ChannelStateClosed,
		channel.ConnectionId,
		channel.CounterpartyChannelId,
		channel.CounterpartyPortId.Clone(),
		channel.Version,
	)
}
