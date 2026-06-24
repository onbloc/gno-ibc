package main

import (
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/smoke"
	"gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	smoke.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(smoke.MockClientType, nil, nil))
}
