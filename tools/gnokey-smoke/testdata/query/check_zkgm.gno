package main

import (
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func main() {
	portID := []byte(zkgm.ProxyPkgPath())
	println("zkgm_registered", core.HasApp(portID))
}
