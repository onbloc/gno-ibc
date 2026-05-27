package zkgm

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
)

type App struct{}

var _ core.IApp = &App{}

func (a *App) OnChannelOpenInit(cur realm, connectionId core.ConnectionId, channelId core.ChannelId, version string, relayer address) {
	ensureImpl()
	ensureVersion(version)
	impl.PreChannelOpenInit(cur, channelId)
}

func (a *App) OnChannelOpenTry(cur realm, connectionId core.ConnectionId, channelId core.ChannelId, version string, counterpartyVersion string, relayer address) {
	ensureImpl()
	ensureVersion(version)
	ensureVersion(counterpartyVersion)
	impl.PreChannelOpenTry(cur, channelId, counterpartyVersion)
}

func (a *App) OnChannelOpenAck(cur realm, channelId core.ChannelId, counterpartyChannelId core.ChannelId, counterpartyVersion string, relayer address) {
	ensureImpl()
	ensureVersion(counterpartyVersion)
	impl.PostChannelOpenAck(cur, channelId, counterpartyChannelId)
}

func (a *App) OnChannelOpenConfirm(cur realm, channelId core.ChannelId, relayer address) {
	ensureImpl()
	impl.PostChannelOpenConfirm(cur, channelId)
}

func (a *App) OnChannelCloseInit(cur realm, channelId core.ChannelId, relayer address) {
	ensureImpl()
	impl.PreChannelCloseInit(cur, channelId)
}

func (a *App) OnChannelCloseConfirm(cur realm, channelId core.ChannelId, relayer address) {
	ensureImpl()
	impl.PostChannelCloseConfirm(cur, channelId)
}

func (a *App) OnRecvPacket(cur realm, packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult {
	if paused {
		return errAck(cur, errors.New("zkgm: paused"))
	}
	if impl == nil {
		return errAck(cur, errors.New("zkgm: impl not set"))
	}
	return impl.Recv(cur, packet, relayer, relayerMsg)
}

func (a *App) OnIntentRecvPacket(cur realm, packet core.Packet, marketMaker address, marketMakerMsg []byte) {
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		panic("zkgm: impl not set")
	}
	impl.IntentRecv(cur, packet, marketMaker, marketMakerMsg)
}

func (a *App) OnAcknowledgementPacket(cur realm, packet core.Packet, ack []byte, relayer address) {
	if impl == nil {
		return
	}
	impl.Ack(cur, packet, ack, relayer)
}

func (a *App) OnTimeoutPacket(cur realm, packet core.Packet, relayer address) {
	if impl == nil {
		return
	}
	impl.Timeout(cur, packet, relayer)
}

func ensureImpl() {
	if impl == nil {
		panic("zkgm: impl not set")
	}
}

func ensureVersion(version string) {
	if version != Version {
		panic("zkgm: unsupported channel version")
	}
}

func errAck(cur realm, err error) core.RecvPacketResult {
	ackBytes, encErr := z.EncodeAck(z.Ack{
		Tag:      u256.NewUint(0),
		InnerAck: []byte(err.Error()),
	})
	if encErr != nil {
		ackBytes = []byte(err.Error())
	}
	return core.NewRecvPacketResult(cur, core.PacketStatusFailure, ackBytes)
}
