// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	upgradeimpl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	stdtesting.SetRealm(stdtesting.NewCodeRealm("gno.land/r/not-onbloc/unionibc/v1/apps/zkgm/v0/loader"))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "outside"), []string{
		zkgm.ProxyPkgPath() + "/v0/impl",
	}))
}

// Error:
// zkgm: bootstrap not permitted for caller: gno.land/r/not-onbloc/unionibc/v1/apps/zkgm/v0/loader
