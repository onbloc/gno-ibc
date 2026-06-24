// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	upgradeimpl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	stdtesting.SetRealm(stdtesting.NewCodeRealm(zkgm.ProductionImplPath()))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "prod-impl"), []string{}))

	println("bootstrapped", zkgm.Bootstrapped())
	println("impl_path", zkgm.ImplPath())
	println("allowed_count", len(zkgm.AllowedImpls()))
}

// Output:
// bootstrapped true
// impl_path gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1
// allowed_count 0
