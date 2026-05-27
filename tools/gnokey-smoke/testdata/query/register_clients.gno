package main

import (
	core "gno.land/r/core/ibc/v1/core"
	cometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
	statelens "gno.land/r/core/ibc/v1/lightclients/statelensics23mpt"
)

func main(cur realm) {
	if !core.HasClient(statelens.ClientType) {
		core.RegisterClient(cross(cur), statelens.ClientType, statelens.NewAdapter(cross(cur)))
	}
	if !core.HasClient(cometbls.ClientType) {
		core.RegisterClient(cross(cur), cometbls.ClientType, cometbls.NewAdapter(cross(cur)))
	}
	println("registered_statelens", core.HasClient(statelens.ClientType))
	println("registered_cometbls", core.HasClient(cometbls.ClientType))
}
