// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	upgradeimpl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	oldImpl := zkgm.ProxyPkgPath() + "/testing/allowed-old"
	newImpl := zkgm.ProxyPkgPath() + "/testing/allowed-new"

	println("[SCENARIO] 1. bootstrap with next implementation allowlisted")
	stdtesting.SetRealm(stdtesting.NewCodeRealm(oldImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "old"), []string{
		oldImpl,
		newImpl,
	}))
	println("[EXPECTED] old_impl_path", zkgm.ImplPath())
	println("[EXPECTED] new_impl_allowed_before", zkgm.InAllowedImpls(newImpl))

	println("")
	println("[SCENARIO] 2. allowed implementation self-registers")
	stdtesting.SetRealm(stdtesting.NewCodeRealm(newImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "new"), []string{
		newImpl,
	}))
	println("[EXPECTED] new_impl_path", zkgm.ImplPath())
	println("[EXPECTED] old_impl_allowed_after", zkgm.InAllowedImpls(oldImpl))
	println("[EXPECTED] new_impl_allowed_after", zkgm.InAllowedImpls(newImpl))
	println("[EXPECTED] render_after", zkgm.Render(""))
}

// Output:
// [SCENARIO] 1. bootstrap with next implementation allowlisted
// [EXPECTED] old_impl_path gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/allowed-old
// [EXPECTED] new_impl_allowed_before true
//
// [SCENARIO] 2. allowed implementation self-registers
// [EXPECTED] new_impl_path gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/allowed-new
// [EXPECTED] old_impl_allowed_after false
// [EXPECTED] new_impl_allowed_after true
// [EXPECTED] render_after new
