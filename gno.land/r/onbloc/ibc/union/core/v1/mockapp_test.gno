package impl

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/types"
)

// mockApp records the channel callbacks the host dispatches to a registered app.
type mockApp struct {
	openInit     int
	openTry      int
	openAck      int
	openConfirm  int
	closeInit    int
	closeConfirm int
}

var (
	_ app.IApp       = (*mockApp)(nil)
	_ app.IIntentApp = (*mockApp)(nil)
)

func (a *mockApp) OnChannelOpenInit(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, relayer address) {
	a.openInit++
}

func (a *mockApp) OnChannelOpenTry(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, counterpartyVersion string, relayer address) {
	a.openTry++
}

func (a *mockApp) OnChannelOpenAck(cur realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId, counterpartyVersion string, relayer address) {
	a.openAck++
}

func (a *mockApp) OnChannelOpenConfirm(cur realm, channelId types.ChannelId, relayer address) {
	a.openConfirm++
}

func (a *mockApp) OnChannelCloseInit(cur realm, channelId types.ChannelId, relayer address) {
	a.closeInit++
}

func (a *mockApp) OnChannelCloseConfirm(cur realm, channelId types.ChannelId, relayer address) {
	a.closeConfirm++
}

func (a *mockApp) OnRecvPacket(cur realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult {
	return types.RecvPacketResult{}
}

func (a *mockApp) OnAcknowledgementPacket(cur realm, packet types.Packet, acknowledgement []byte, relayer address) {
}

func (a *mockApp) OnTimeoutPacket(cur realm, packet types.Packet, relayer address) {}

func (a *mockApp) OnIntentRecvPacket(cur realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult {
	return types.RecvPacketResult{}
}
