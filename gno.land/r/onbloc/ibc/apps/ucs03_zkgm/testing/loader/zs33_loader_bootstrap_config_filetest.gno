// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/loader
package loader

import (
	zkgm "gno.land/r/onbloc/ibc/apps/ucs03_zkgm"
	upgradeimpl "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "loader"), []string{
		"gno.land/r/onbloc/ibc/core",
		"gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1",
	}))

	println("[SCENARIO] 1. loader bootstraps proxy")
	println("[EXPECTED] bootstrapped", zkgm.Bootstrapped())
	println("[EXPECTED] impl_path", zkgm.ImplPath())
	println("[EXPECTED] core_allowed", zkgm.InAllowedImpls("gno.land/r/onbloc/ibc/core"))
	println("[EXPECTED] impl_allowed", zkgm.InAllowedImpls("gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1"))
}

// Output:
// [SCENARIO] 1. loader bootstraps proxy
// [EXPECTED] bootstrapped true
// [EXPECTED] impl_path gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/loader
// [EXPECTED] core_allowed true
// [EXPECTED] impl_allowed true
