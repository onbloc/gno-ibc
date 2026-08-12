package main

import (
	"gno.land/r/onbloc/ibc/testing/mock/lightclient"
	"gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	lightclient.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(lightclient.MockClientType, []byte{1}, []byte{1}))
}
