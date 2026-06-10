package upgradeimpl

import (
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

type Impl struct {
	label string
}

func New(cur realm, label string) zkgm.ZkgmImpl {
	return &Impl{label: label}
}

func (i *Impl) PreChannelOpenInit(cur realm, channelId core.ChannelId) {}

func (i *Impl) PreChannelOpenTry(cur realm, channelId core.ChannelId, counterpartyVersion string) {}

func (i *Impl) PostChannelOpenAck(cur realm, channelId core.ChannelId, counterpartyChannelId core.ChannelId) {
}

func (i *Impl) PostChannelOpenConfirm(cur realm, channelId core.ChannelId) {}

func (i *Impl) PreChannelCloseInit(cur realm, channelId core.ChannelId) {}

func (i *Impl) PostChannelCloseConfirm(cur realm, channelId core.ChannelId) {}

func (i *Impl) Recv(cur realm, packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, []byte(i.label))
}

func (i *Impl) IntentRecv(cur realm, packet core.Packet, marketMaker address, marketMakerMsg []byte) core.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, []byte(i.label))
}

func (i *Impl) Ack(cur realm, packet core.Packet, ack []byte, relayer address) {}

func (i *Impl) Timeout(cur realm, packet core.Packet, relayer address) {}

func (i *Impl) Send(cur realm, req zkgm.SendRequest) ([]byte, error) {
	return []byte(i.label), nil
}

func (i *Impl) Render(pkgpath string, path string) string {
	return i.label
}
