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
	panic("not implemented")
}

func (v *ZkgmV0) Send(req zkgm.SendRequest) (zkgm.SendResult, error) {
	panic("not implemented")
}

func (v *ZkgmV0) PostSend(req zkgm.SendRequest, res zkgm.SendResult) {
}

func (v *ZkgmV0) PreRecv(req zkgm.RecvRequest) error {
	panic("not implemented")
}

func (v *ZkgmV0) Recv(req zkgm.RecvRequest) (types.RecvPacketResult, error) {
	panic("not implemented")
}

func (v *ZkgmV0) PostRecv(req zkgm.RecvRequest, res types.RecvPacketResult) {
}

func (v *ZkgmV0) PreAck(req zkgm.AckRequest) error {
	panic("not implemented")
}

func (v *ZkgmV0) Ack(req zkgm.AckRequest) error {
	panic("not implemented")
}

func (v *ZkgmV0) PostAck(req zkgm.AckRequest) {
}

func (v *ZkgmV0) PreTimeout(req zkgm.TimeoutRequest) error {
	panic("not implemented")
}

func (v *ZkgmV0) Timeout(req zkgm.TimeoutRequest) error {
	panic("not implemented")
}

func (v *ZkgmV0) PostTimeout(req zkgm.TimeoutRequest) {
}

func (v *ZkgmV0) Render(pkgpath string, path string) string {
	return "zkgm v0 - not implemented"
}

var _ zkgm.ZkgmImpl = &ZkgmV0{}
