package main

import (
	"chain"

	"gno.land/p/onbloc/access/manager"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

func main(cur realm) {
	access.GrantRole(cross(cur), manager.AdminRole, cur.Address())
	access.GrantRole(cross(cur), access.RelayerRole, cur.Address())
	access.GrantRole(cross(cur), manager.AdminRole, chain.PackageAddress("gno.land/r/onbloc/ibc/union/core"))
	access.GrantRole(cross(cur), manager.AdminRole, chain.PackageAddress("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"))
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress("gno.land/r/onbloc/ibc/union/core"))
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress("gno.land/r/onbloc/ibc/union/lightclients/cometbls"))
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress("gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt"))
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress("gno.land/r/onbloc/ibc/testing/mock/lightclient"))

	core.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/core/v1")
	zkgm.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1")
	println("core_impl_updated")
	println("zkgm_impl_updated")
}
