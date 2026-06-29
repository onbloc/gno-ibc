// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// reject_non_admin_update_impl_filetest is an EXCEPTION-path upgrade scenario for
// the current admin-gated impl model. zkgm.UpdateImpl is gated by the access
// manager on the "update_impl" selector (defaulting to AdminRole). A non-admin
// caller cannot install or re-point the impl — the terminating panic matched by the
// // Error: directive. (This replaces the legacy allowed-impls "removed/unallowed
// impl rejected" and "bootstrap outside namespace" tests under the current model.)

import (
	"testing"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const (
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	nonAdminAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu") // holds no role
)

func main(cur realm) {
	println("[SCENARIO] 1. A non-admin attempts to install the impl -> rejected")
	testing.SetRealm(testing.NewUserRealm(nonAdminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
}

// Output:
// [SCENARIO] 1. A non-admin attempts to install the impl -> rejected

// Error:
// access manager unauthorized call: g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu is not authorized to call update_impl on gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
