package upgradeimpl

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

const pkgPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/upgradeimpl"

type Impl struct {
	label string
}

func New(cur realm, label string) zkgm.ZkgmImpl {
	return &Impl{label: label}
}

func PkgPath() string {
	return pkgPath
}

func MintVoucher(cur realm, ibcDenom string, receiver address, amount *u256.Uint) {
	if err := zkgm.MintVoucher(cross(cur), ibcDenom, ibcDenom, [32]byte{}, "", "UPGRADE", 0, receiver.String(), amount); err != nil {
		panic(err)
	}
}

func (i *Impl) PreChannelOpenInit(cur realm, channelId types.ChannelId) {}

func (i *Impl) PreChannelOpenTry(cur realm, channelId types.ChannelId, counterpartyVersion string) {}

func (i *Impl) PostChannelOpenAck(cur realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId) {
}

func (i *Impl) PostChannelOpenConfirm(cur realm, channelId types.ChannelId) {}

func (i *Impl) PreChannelCloseInit(cur realm, channelId types.ChannelId) {}

func (i *Impl) PostChannelCloseConfirm(cur realm, channelId types.ChannelId) {}

func (i *Impl) Recv(cur realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), types.PacketStatusSuccess, []byte(i.label))
}

func (i *Impl) IntentRecv(cur realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), types.PacketStatusSuccess, []byte(i.label))
}

func (i *Impl) Ack(cur realm, packet types.Packet, ack []byte, relayer address) {}

func (i *Impl) Timeout(cur realm, packet types.Packet, relayer address) {}

func (i *Impl) Send(cur realm, req zkgm.SendRequest) ([]byte, error) {
	return []byte(i.label), nil
}

func (i *Impl) Render(pkgpath string, path string) string {
	return i.label
}
