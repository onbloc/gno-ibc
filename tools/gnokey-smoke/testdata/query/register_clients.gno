package main

import (
	"gno.land/r/onbloc/ibc/union/lightclients/cometbls"
	statelens "gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt"
	"gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	if !core.HasClient(statelens.ClientType) {
		statelens.RegisterClient(cross(cur))
	}
	if !core.HasClient(cometbls.ClientType) {
		cometbls.RegisterClient(cross(cur))
	}
	println("registered_statelens", core.HasClient(statelens.ClientType))
	println("registered_cometbls", core.HasClient(cometbls.ClientType))
}
