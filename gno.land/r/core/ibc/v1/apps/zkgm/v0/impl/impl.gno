package impl

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
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

func (v *ZkgmV1) Recv(packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult {
	zp, err := z.DecodeZkgmPacket(packet.Data)
	if err != nil {
		return errResult(err)
	}
	res, err := v.dispatchExecute(packet, relayer, relayerMsg, zp.Path, zp.Salt, zp.Instruction, false)
	if err != nil {
		return errResult(err)
	}
	return res
}

func (v *ZkgmV1) Ack(packet core.Packet, ack []byte, relayer address) {
	zp, err := z.DecodeZkgmPacket(packet.Data)
	if err != nil {
		panic(err.Error())
	}
	if v.handleForwardChild(packet, zp, ack) {
		return
	}

	if err := v.dispatchAck(packet, zp.Path, zp.Salt, zp.Instruction, ack); err != nil {
		panic(err.Error())
	}
}

func (v *ZkgmV1) Timeout(packet core.Packet, relayer address) {
	zp, err := z.DecodeZkgmPacket(packet.Data)
	if err != nil {
		panic(err.Error())
	}
	if v.handleForwardChild(packet, zp, universalErrorAck()) {
		return
	}

	if err := v.dispatchTimeout(packet, zp.Path, zp.Salt, zp.Instruction); err != nil {
		panic(err.Error())
	}
}

// IntentRecv handles a market-maker fast-path delivery. The new core spec
// dispatches IntentPacketRecv without a relayer proof; impl reuses the same
// dispatch chain with intent=true so each opcode can render an only-maker
// outcome where appropriate. The result is dropped because the new
// OnIntentRecvPacket callback has no return.
func (v *ZkgmV1) IntentRecv(packet core.Packet, marketMaker address, marketMakerMsg []byte) {
	zp, err := z.DecodeZkgmPacket(packet.Data)
	if err != nil {
		panic(err.Error())
	}
	if _, err := v.dispatchExecute(packet, marketMaker, marketMakerMsg, zp.Path, zp.Salt, zp.Instruction, true); err != nil {
		panic(err.Error())
	}
}

func (v *ZkgmV1) Send(req zkgm.SendRequest) ([]byte, error) {
	if err := v.dispatchVerify(req.ChannelId, req.Sender, parseCoins(req.SentCoins), req.Salt, req.Instruction); err != nil {
		return nil, err
	}

	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        req.Salt,
		Path:        u256.Zero(),
		Instruction: req.Instruction,
	})
	if err != nil {
		return nil, err
	}

	return data, nil
}

func (v *ZkgmV1) Render(pkgpath string, path string) string {
	if path == "" {
		return "zkgm v1"
	}
	return "zkgm/v1: render path not found: " + path
}

func errResult(err error) core.RecvPacketResult {
	return failureResult([]byte(err.Error()))
}

var _ zkgm.ZkgmImpl = &ZkgmV1{}
