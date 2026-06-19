package zkgm

import (
	app "gno.land/p/onbloc/ibc/union/app"
	types "gno.land/p/onbloc/ibc/union/types"
)

// app.gno is the App receiver surface: the core-driven half of the proxy. core
// holds this App reference permanently (its port is keyed by the proxy pkgpath
// and re-registration is rejected), so App is the stable IBC identity and must
// never carry business logic. Every receiver gates on assertIsIBCHost and then
// delegates to the installed impl; the packet callbacks (recv/intent/ack/timeout)
// additionally check assertNotPaused. Channel handshake is intentionally allowed
// while paused so channels can still be managed. Logic lives in the impl realm;
// authority and funds live in the proxy. See assert.gno for the gates and
// upgrade.gno for the swap point.
type App struct{}

var (
	_ app.IApp       = &App{}
	_ app.IIntentApp = &App{}
)

func (a *App) OnChannelOpenInit(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, relayer address) {
	assertIsIBCHost(cur)
	impl.OnChannelOpenInit(0, cur, connectionId, channelId, version, relayer)
}

func (a *App) OnChannelOpenTry(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, counterpartyVersion string, relayer address) {
	assertIsIBCHost(cur)
	impl.OnChannelOpenTry(0, cur, connectionId, channelId, version, counterpartyVersion, relayer)
}

func (a *App) OnChannelOpenAck(cur realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId, counterpartyVersion string, relayer address) {
	assertIsIBCHost(cur)
	impl.OnChannelOpenAck(0, cur, channelId, counterpartyChannelId, counterpartyVersion, relayer)
}

func (a *App) OnChannelOpenConfirm(cur realm, channelId types.ChannelId, relayer address) {
	assertIsIBCHost(cur)
	impl.OnChannelOpenConfirm(0, cur, channelId, relayer)
}

func (a *App) OnChannelCloseInit(cur realm, channelId types.ChannelId, relayer address) {
	assertIsIBCHost(cur)
	impl.OnChannelCloseInit(0, cur, channelId, relayer)
}

func (a *App) OnChannelCloseConfirm(cur realm, channelId types.ChannelId, relayer address) {
	assertIsIBCHost(cur)
	impl.OnChannelCloseConfirm(0, cur, channelId, relayer)
}

func (a *App) OnRecvPacket(cur realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult {
	assertIsIBCHost(cur)
	assertNotPaused()
	return impl.OnRecvPacket(0, cur, packet, relayer, relayerMsg)
}

func (a *App) OnAcknowledgementPacket(cur realm, packet types.Packet, acknowledgement []byte, relayer address) {
	assertIsIBCHost(cur)
	assertNotPaused()
	impl.OnAcknowledgementPacket(0, cur, packet, acknowledgement, relayer)
}

func (a *App) OnTimeoutPacket(cur realm, packet types.Packet, relayer address) {
	assertIsIBCHost(cur)
	assertNotPaused()
	impl.OnTimeoutPacket(0, cur, packet, relayer)
}

func (a *App) OnIntentRecvPacket(cur realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult {
	assertIsIBCHost(cur)
	assertNotPaused()
	return impl.OnIntentRecvPacket(0, cur, packet, marketMaker, marketMakerMsg)
}
