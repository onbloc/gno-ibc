package impl

import (
	"chain/runtime"

	"gno.land/p/aib/ibc/types"

	z "gno.land/p/gnoswap/ibc/zkgm"
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
	return v.sendTokenOrderV2(req)
}

func (v *ZkgmV0) PostSend(req zkgm.SendRequest, res zkgm.SendResult) {
}

func (v *ZkgmV0) PreRecv(req zkgm.RecvRequest) error {
	return nil
}

func (v *ZkgmV0) Recv(req zkgm.RecvRequest) (types.RecvPacketResult, error) {
	packet, err := decodePacket(req.Payload)
	if err != nil {
		return types.RecvPacketResult{}, err
	}
	order, err := decodeOrder(packet)
	if err != nil {
		return types.RecvPacketResult{}, err
	}
	return v.executeTokenOrderV2(req, packet.Path, order)
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
	order, err := decodeOrder(packet)
	if err != nil {
		return err
	}
	if isUniversalErrorAck(req.Acknowledgement) {
		return v.refundV2(req.SourceClient, packet.Path, order)
	}
	ack, err := z.DecodeAck(req.Acknowledgement)
	if err != nil {
		return err
	}
	return v.acknowledgeTokenOrderV2(req.SourceClient, packet.Path, order, ack)
}

func (v *ZkgmV0) PostAck(req zkgm.AckRequest) {
}

func (v *ZkgmV0) PreTimeout(req zkgm.TimeoutRequest) error {
	return nil
}

func (v *ZkgmV0) Timeout(req zkgm.TimeoutRequest) error {
	packet, err := decodePacket(req.Payload)
	if err != nil {
		return err
	}
	order, err := decodeOrder(packet)
	if err != nil {
		return err
	}
	return v.refundV2(req.SourceClient, packet.Path, order)
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
