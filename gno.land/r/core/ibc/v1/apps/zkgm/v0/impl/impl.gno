package impl

import (
	"chain/runtime"
	"errors"

	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

type ZkgmV1 struct{}

var instance = &ZkgmV1{}

func GetInstance() *ZkgmV1 {
	if runtime.CurrentRealm().PkgPath() != "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader" {
		panic("not allowed")
	}
	return instance
}

func (v *ZkgmV1) PreChannelOpenInit(channelId core.ChannelId) {}

func (v *ZkgmV1) PreChannelOpenTry(channelId core.ChannelId, counterpartyVersion string) {}

func (v *ZkgmV1) PostChannelOpenAck(channelId core.ChannelId, counterpartyChannelId core.ChannelId) {}

func (v *ZkgmV1) PostChannelOpenConfirm(channelId core.ChannelId) {}

func (v *ZkgmV1) PreChannelCloseInit(channelId core.ChannelId) {}

func (v *ZkgmV1) PostChannelCloseConfirm(channelId core.ChannelId) {}

func (v *ZkgmV1) Recv(packet core.Packet, relayer address, relayerMsg core.Bytes) core.RecvPacketResult {
	return errResult(errors.New("zkgm/v1: recv not implemented"))
}

func (v *ZkgmV1) Ack(packet core.Packet, ack core.Bytes, relayer address) {}

func (v *ZkgmV1) Timeout(packet core.Packet, relayer address) {}

func (v *ZkgmV1) Send(channelId core.ChannelId, data core.Bytes, timeoutTimestamp core.Timestamp) (core.Packet, error) {
	return core.PacketSend(cross, core.MsgPacketSend{
		SourceChannelId:  channelId,
		TimeoutTimestamp: timeoutTimestamp,
		Data:             data,
	}), nil
}

func (v *ZkgmV1) Render(pkgpath string, path string) string {
	if path == "" {
		return "zkgm v1"
	}
	return "zkgm/v1: render path not found: " + path
}

func errResult(err error) core.RecvPacketResult {
	return core.NewRecvPacketResult(cross, core.PacketStatusFailure, []byte(err.Error()))
}

var _ zkgm.ZkgmImpl = &ZkgmV1{}
