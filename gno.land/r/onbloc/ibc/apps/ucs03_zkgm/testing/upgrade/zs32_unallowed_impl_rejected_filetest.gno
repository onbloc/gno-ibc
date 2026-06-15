// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	zkgm "gno.land/r/onbloc/ibc/apps/ucs03_zkgm"
	upgradeimpl "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	currentImpl := zkgm.ProxyPkgPath() + "/testing/current"

	stdtesting.SetRealm(stdtesting.NewCodeRealm(currentImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "current"), []string{
		currentImpl,
	}))

	stdtesting.SetRealm(stdtesting.NewCodeRealm(zkgm.ProxyPkgPath() + "/testing/not-allowed"))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "denied"), nil))
}

// Error:
// permission denied for prev realm: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/not-allowed
