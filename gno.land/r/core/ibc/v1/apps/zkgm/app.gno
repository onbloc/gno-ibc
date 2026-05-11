package zkgm

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
)

type App struct{}

var _ core.IApp = &App{}

func (a *App) OnChannelOpenInit(connectionId core.ConnectionId, channelId core.ChannelId, version string, relayer address) {
	ensureImpl()
	ensureVersion(version)
	impl.PreChannelOpenInit(channelId)
}

func (a *App) OnChannelOpenTry(connectionId core.ConnectionId, channelId core.ChannelId, version string, counterpartyVersion string, relayer address) {
	ensureImpl()
	ensureVersion(version)
	ensureVersion(counterpartyVersion)
	impl.PreChannelOpenTry(channelId, counterpartyVersion)
}

func (a *App) OnChannelOpenAck(channelId core.ChannelId, counterpartyChannelId core.ChannelId, counterpartyVersion string, relayer address) {
	ensureImpl()
	ensureVersion(counterpartyVersion)
	impl.PostChannelOpenAck(channelId, counterpartyChannelId)
}

func (a *App) OnChannelOpenConfirm(channelId core.ChannelId, relayer address) {
	ensureImpl()
	impl.PostChannelOpenConfirm(channelId)
}

func (a *App) OnChannelCloseInit(channelId core.ChannelId, relayer address) {
	ensureImpl()
	impl.PreChannelCloseInit(channelId)
}

func (a *App) OnChannelCloseConfirm(channelId core.ChannelId, relayer address) {
	ensureImpl()
	impl.PostChannelCloseConfirm(channelId)
}

func (a *App) OnRecvPacket(packet core.Packet, relayer address, relayerMsg core.Bytes) core.RecvPacketResult {
	if paused {
		return errAck(errors.New("zkgm: paused"))
	}
	if impl == nil {
		return errAck(errors.New("zkgm: impl not set"))
	}
	return impl.Recv(packet, relayer, relayerMsg)
}

func (a *App) OnAcknowledgementPacket(packet core.Packet, ack core.Bytes, relayer address) {
	if impl == nil {
		return
	}
	impl.Ack(packet, ack, relayer)
}

func (a *App) OnTimeoutPacket(packet core.Packet, relayer address) {
	if impl == nil {
		return
	}
	impl.Timeout(packet, relayer)
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

func errAck(err error) core.RecvPacketResult {
	ackBytes, encErr := z.EncodeAck(z.Ack{
		Tag:      u256.NewUint(0),
		InnerAck: []byte(err.Error()),
	})
	if encErr != nil {
		ackBytes = []byte(err.Error())
	}
	return core.NewRecvPacketResult(cross, core.PacketStatusFailure, ackBytes)
}
