package zkgm

import (
	app "gno.land/p/onbloc/ibc/union/app"
	types "gno.land/p/onbloc/ibc/union/types"
)

// app.gno is the App receiver surface: the core-driven half of the proxy. core
// holds this App reference permanently (its port is keyed by the proxy pkgpath
// and re-registration is rejected), so App is the stable IBC identity and must
// never carry business logic. Every receiver gates on assertIsIBCHost and checks
// the pause state before delegating to the installed impl or rejecting channel
// close. Logic lives in the impl realm; authority and funds live in the proxy.
// See assert.gno for the gates and upgrade.gno for the swap point.
type App struct{}

var (
	_ app.IApp       = &App{}
	_ app.IIntentApp = &App{}
)

func (a *App) OnChannelOpenInit(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, relayer address) {
	assertIsIBCHost(cur)

	if paused {
		panic("zkgm: paused")
	}

	mustGetImpl().OnChannelOpenInit(0, cur, connectionId, channelId, version, relayer)
}

func (a *App) OnChannelOpenTry(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, counterpartyVersion string, relayer address) {
	assertIsIBCHost(cur)

	if paused {
		panic("zkgm: paused")
	}

	mustGetImpl().OnChannelOpenTry(0, cur, connectionId, channelId, version, counterpartyVersion, relayer)
}

func (a *App) OnChannelOpenAck(cur realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId, counterpartyVersion string, relayer address) {
	assertIsIBCHost(cur)

	if paused {
		panic("zkgm: paused")
	}

	mustGetImpl().OnChannelOpenAck(0, cur, channelId, counterpartyChannelId, counterpartyVersion, relayer)
}

func (a *App) OnChannelOpenConfirm(cur realm, channelId types.ChannelId, relayer address) {
	assertIsIBCHost(cur)

	if paused {
		panic("zkgm: paused")
	}

	mustGetImpl().OnChannelOpenConfirm(0, cur, channelId, relayer)
}

func (a *App) OnChannelCloseInit(cur realm, channelId types.ChannelId, relayer address) {
	assertIsIBCHost(cur)

	if paused {
		panic("zkgm: paused")
	}

	panic("zkgm: the show must go on")
}

func (a *App) OnChannelCloseConfirm(cur realm, channelId types.ChannelId, relayer address) {
	assertIsIBCHost(cur)

	if paused {
		panic("zkgm: paused")
	}

	panic("zkgm: the show must go on")
}

func (a *App) OnRecvPacket(cur realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult {
	assertIsIBCHost(cur)
	assertNotPaused()

	return mustGetImpl().OnRecvPacket(0, cur, packet, relayer, relayerMsg)
}

func (a *App) OnAcknowledgementPacket(cur realm, packet types.Packet, acknowledgement []byte, relayer address) {
	assertIsIBCHost(cur)
	assertNotPaused()
	mustGetImpl().OnAcknowledgementPacket(0, cur, packet, acknowledgement, relayer)
}

func (a *App) OnTimeoutPacket(cur realm, packet types.Packet, relayer address) {
	assertIsIBCHost(cur)
	assertNotPaused()
	mustGetImpl().OnTimeoutPacket(0, cur, packet, relayer)
}

func (a *App) OnIntentRecvPacket(cur realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult {
	assertIsIBCHost(cur)
	assertNotPaused()

	return mustGetImpl().OnIntentRecvPacket(0, cur, packet, marketMaker, marketMakerMsg)
}
