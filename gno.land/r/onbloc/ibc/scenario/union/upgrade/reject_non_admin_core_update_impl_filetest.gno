// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// reject_non_admin_core_update_impl_filetest covers the core proxy:
// only the admin can install or re-point the core implementation.

import (
	"testing"

	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	nonAdminAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
)

func main(cur realm) {
	println("[SCENARIO] 1. A non-admin attempts to install the core impl -> rejected")
	testing.SetRealm(testing.NewUserRealm(nonAdminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
}

// Output:
// [SCENARIO] 1. A non-admin attempts to install the core impl -> rejected

// Error:
// access manager unauthorized call: g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu is not authorized to call update_impl on gno.land/r/onbloc/ibc/union/core
