package zkgm

import (
	"errors"

	z "gno.land/p/onbloc/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
)

type App struct{}

var (
	_ core.IApp       = &App{}
	_ core.IIntentApp = &App{}
)

func (a *App) OnChannelOpenInit(cur realm, connectionId core.ConnectionId, channelId core.ChannelId, version string, relayer address) {
	requireCoreCaller(cur, "channel open init")
	ensureImpl()
	ensureVersion(version)
	impl.PreChannelOpenInit(cross(cur), channelId)
}

func (a *App) OnChannelOpenTry(cur realm, connectionId core.ConnectionId, channelId core.ChannelId, version string, counterpartyVersion string, relayer address) {
	requireCoreCaller(cur, "channel open try")
	ensureImpl()
	ensureVersion(version)
	ensureVersion(counterpartyVersion)
	impl.PreChannelOpenTry(cross(cur), channelId, counterpartyVersion)
}

func (a *App) OnChannelOpenAck(cur realm, channelId core.ChannelId, counterpartyChannelId core.ChannelId, counterpartyVersion string, relayer address) {
	requireCoreCaller(cur, "channel open ack")
	ensureImpl()
	ensureVersion(counterpartyVersion)
	impl.PostChannelOpenAck(cross(cur), channelId, counterpartyChannelId)
}

func (a *App) OnChannelOpenConfirm(cur realm, channelId core.ChannelId, relayer address) {
	requireCoreCaller(cur, "channel open confirm")
	ensureImpl()
	impl.PostChannelOpenConfirm(cross(cur), channelId)
}

func (a *App) OnChannelCloseInit(cur realm, channelId core.ChannelId, relayer address) {
	requireCoreCaller(cur, "channel close init")
	ensureImpl()
	impl.PreChannelCloseInit(cross(cur), channelId)
}

func (a *App) OnChannelCloseConfirm(cur realm, channelId core.ChannelId, relayer address) {
	requireCoreCaller(cur, "channel close confirm")
	ensureImpl()
	impl.PostChannelCloseConfirm(cross(cur), channelId)
}

func (a *App) OnRecvPacket(cur realm, packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult {
	requireCoreCaller(cur, "recv")
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		return errAck(cur, errors.New("zkgm: impl not set"))
	}
	return impl.Recv(cross(cur), packet, relayer, relayerMsg)
}

func (a *App) OnIntentRecvPacket(cur realm, packet core.Packet, marketMaker address, marketMakerMsg []byte) core.RecvPacketResult {
	requireCoreCaller(cur, "intent recv")
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		return errAck(cur, errors.New("zkgm: impl not set"))
	}
	return impl.IntentRecv(cross(cur), packet, marketMaker, marketMakerMsg)
}

func (a *App) OnAcknowledgementPacket(cur realm, packet core.Packet, ack []byte, relayer address) {
	requireCoreCaller(cur, "ack")
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		return
	}
	impl.Ack(cross(cur), packet, ack, relayer)
}

func (a *App) OnTimeoutPacket(cur realm, packet core.Packet, relayer address) {
	requireCoreCaller(cur, "timeout")
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		return
	}
	impl.Timeout(cross(cur), packet, relayer)
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

// requireCoreCaller panics unless the immediate caller is the core realm.
//
// App callbacks are expected to be reached only through core handlers. This
// check prevents direct invocation from other realms and preserves the core
// security boundary.
func requireCoreCaller(cur realm, action string) {
	caller := cur.Previous().PkgPath()
	if caller != core.PkgPath(cross(cur)) {
		panic("zkgm: only core can " + action + ", got " + caller)
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
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusFailure, ackBytes)
}
