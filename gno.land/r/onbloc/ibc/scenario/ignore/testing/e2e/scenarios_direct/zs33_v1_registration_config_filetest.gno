// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct
package scenarios_direct

import (
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	impl.Register(cross(cur))

	println("[SCENARIO] 1. v1 registers proxy")
	println("[EXPECTED] bootstrapped", zkgm.Bootstrapped())
	println("[EXPECTED] impl_path", zkgm.ImplPath())
	println("[EXPECTED] allowed_count", len(zkgm.AllowedImpls()))
	println("[EXPECTED] loader_allowed", zkgm.InAllowedImpls("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"))
}

// Output:
// [SCENARIO] 1. v1 registers proxy
// [EXPECTED] bootstrapped true
// [EXPECTED] impl_path gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1
// [EXPECTED] allowed_count 0
// [EXPECTED] loader_allowed false
