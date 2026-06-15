// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	zkgm "gno.land/r/onbloc/ibc/apps/ucs03_zkgm"
	upgradeimpl "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	stdtesting.SetRealm(stdtesting.NewCodeRealm(zkgm.ProductionLoaderPath()))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "prod-loader"), nil))
}

// Error:
// zkgm: production loader bootstrap must install allowed impls
