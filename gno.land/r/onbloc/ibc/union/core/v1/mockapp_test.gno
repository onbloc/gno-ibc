package v1

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/types"
)

// mockApp records the callbacks the host dispatches to a registered app and lets
// tests configure the recv result.
type mockApp struct {
	openInit     int
	openTry      int
	openAck      int
	openConfirm  int
	closeInit    int
	closeConfirm int

	recvCalls       int
	intentRecvCalls int
	ackCalls        int
	timeoutCalls    int

	recvStatus types.PacketStatus // zero -> Success
	recvAck    []byte             // empty -> "ack" for sync results
	recvAckSet bool               // allow tests to force an empty sync ack
}

func (a *mockApp) recvResult() types.RecvPacketResult {
	status := a.recvStatus
	if status == 0 {
		status = types.PacketStatusSuccess
	}
	ack := a.recvAck
	if len(ack) == 0 && !a.recvAckSet && status != types.PacketStatusAsync {
		ack = []byte("ack")
	}
	return types.RecvPacketResult{Status: status, Acknowledgement: ack}
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
	a.recvCalls++
	return a.recvResult()
}

func (a *mockApp) OnAcknowledgementPacket(cur realm, packet types.Packet, acknowledgement []byte, relayer address) {
	a.ackCalls++
}

func (a *mockApp) OnTimeoutPacket(cur realm, packet types.Packet, relayer address) {
	a.timeoutCalls++
}

func (a *mockApp) OnIntentRecvPacket(cur realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult {
	a.intentRecvCalls++
	return a.recvResult()
}
