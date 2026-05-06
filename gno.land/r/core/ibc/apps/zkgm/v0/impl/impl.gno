package impl

import (
	"chain/runtime"

	"gno.land/p/aib/ibc/types"

	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

type ZkgmV0 struct{}

var instance = &ZkgmV0{}

func GetInstance() *ZkgmV0 {
	if runtime.CurrentRealm().PkgPath() != "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader" {
		panic("not allowed")
	}
	return instance
}

func (v *ZkgmV0) PreSend(req zkgm.SendRequest) error {
	return nil
}

func (v *ZkgmV0) Send(req zkgm.SendRequest) (zkgm.SendResult, error) {
	if err := v.dispatchVerify(req.ChannelID, req.Sender, parseCoins(req.SentCoins), nil, req.Instruction); err != nil {
		return zkgm.SendResult{}, err
	}
	return v.sendPacket(req)
}

func (v *ZkgmV0) PostSend(req zkgm.SendRequest, res zkgm.SendResult) {}

func (v *ZkgmV0) PreRecv(req zkgm.RecvRequest) error {
	return nil
}

func (v *ZkgmV0) Recv(req zkgm.RecvRequest) (types.RecvPacketResult, error) {
	packet, err := decodePacket(req.Payload)
	if err != nil {
		return types.RecvPacketResult{}, err
	}
	return v.dispatchExecute(req, packet.Path, packet.Salt, packet.Instruction, false)
}

func (v *ZkgmV0) PostRecv(req zkgm.RecvRequest, res types.RecvPacketResult) {}

func (v *ZkgmV0) PreAck(req zkgm.AckRequest) error {
	return nil
}

func (v *ZkgmV0) Ack(req zkgm.AckRequest) error {
	packet, err := decodePacket(req.Payload)
	if err != nil {
		return err
	}
	if handleForwardChildAck(req, packet) {
		return nil
	}
	return v.dispatchAck(req, packet.Path, packet.Salt, packet.Instruction, req.Acknowledgement)
}

func (v *ZkgmV0) PostAck(req zkgm.AckRequest) {}

func (v *ZkgmV0) PreTimeout(req zkgm.TimeoutRequest) error {
	return nil
}

func (v *ZkgmV0) Timeout(req zkgm.TimeoutRequest) error {
	packet, err := decodePacket(req.Payload)
	if err != nil {
		return err
	}
	if handleForwardChildTimeout(req, packet) {
		return nil
	}
	return v.dispatchTimeout(req, packet.Path, packet.Salt, packet.Instruction)
}

func (v *ZkgmV0) PostTimeout(req zkgm.TimeoutRequest) {
}

func (v *ZkgmV0) Render(pkgpath string, path string) string {
	if path == "" {
		return "zkgm v0"
	}
	return "zkgm/v0: render path not found: " + path
}

var _ zkgm.ZkgmImpl = &ZkgmV0{}
