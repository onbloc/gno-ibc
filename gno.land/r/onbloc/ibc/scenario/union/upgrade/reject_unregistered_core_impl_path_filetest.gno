// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// reject_unregistered_core_impl_path_filetest covers the core proxy:
// even the admin can only install an implementation path registered by an impl
// realm constructor.

import (
	"testing"

	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	unregisteredCorePath = "gno.land/r/onbloc/ibc/union/core/v99"
)

func main(cur realm) {
	println("[SCENARIO] 1. The admin installs a core impl at an unregistered path -> rejected")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), unregisteredCorePath)
}

// Output:
// [SCENARIO] 1. The admin installs a core impl at an unregistered path -> rejected

// Error:
// impl constructor not found
