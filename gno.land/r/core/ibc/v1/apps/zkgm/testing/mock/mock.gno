package mock

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

type Receiver struct {
	Calls int
}

var receiver = &Receiver{}

func init() {
	zkgm.RegisterReceiver(cross, receiver)
}

func (r *Receiver) OnZkgm(cur realm, env z.CallEnv, calldata []byte) ([]byte, error) {
	r.Calls++
	return []byte("ok"), nil
}

func Calls(cur realm) int {
	return receiver.Calls
}
