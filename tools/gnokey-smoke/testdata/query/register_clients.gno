package main

import (
	core "gno.land/r/onbloc/unionibc/v1/core"
	cometbls "gno.land/r/onbloc/unionibc/v1/lightclients/cometbls"
	statelens "gno.land/r/onbloc/unionibc/v1/lightclients/statelensics23mpt"
)

func main(cur realm) {
	if !core.HasClient(statelens.ClientType) {
		statelens.Register(cross(cur))
	}
	if !core.HasClient(cometbls.ClientType) {
		cometbls.Register(cross(cur))
	}
	println("registered_statelens", core.HasClient(statelens.ClientType))
	println("registered_cometbls", core.HasClient(cometbls.ClientType))
}
