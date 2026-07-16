package main

import (
	cometbls "gno.land/r/onbloc/ibc/union/lightclients/cometbls"
	statelens "gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	core.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/core/v1")
	zkgm.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1")
	if !core.HasApp([]byte(zkgm.ProxyPkgPath())) {
		zkgm.RegisterCoreApp(cross(cur))
	}
	if !core.HasClient(cometbls.ClientType) {
		cometbls.RegisterClient(cross(cur))
	}
	if !core.HasClient(statelens.ClientType) {
		statelens.RegisterClient(cross(cur))
	}
}
