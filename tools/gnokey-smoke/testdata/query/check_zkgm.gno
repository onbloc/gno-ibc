package main

import (
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	"gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	portID := []byte(zkgm.ProxyPkgPath())
	if !core.HasApp(portID) {
		zkgm.RegisterCoreApp(cross(cur))
	}
	println("zkgm_registered", core.HasApp(portID))
}
