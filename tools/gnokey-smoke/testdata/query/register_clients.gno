package main

import (
	core "gno.land/r/core/ibc/v1/core"
	cometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
	statelens "gno.land/r/core/ibc/v1/lightclients/statelensics23mpt"
)

func main() {
	if !core.HasClient(statelens.ClientType) {
		core.RegisterClient(cross, statelens.ClientType, statelens.Adapter{})
	}
	if !core.HasClient(cometbls.ClientType) {
		core.RegisterClient(cross, cometbls.ClientType, cometbls.Adapter{})
	}
	println("registered_statelens", core.HasClient(statelens.ClientType))
	println("registered_cometbls", core.HasClient(cometbls.ClientType))
}
