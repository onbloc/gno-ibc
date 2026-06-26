// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// reject_unregistered_impl_path_filetest is an EXCEPTION-path upgrade scenario for
// the current admin-gated impl model. UpdateImpl can only install a path whose
// constructor was registered by that impl's init (RegisterImpl). Installing an
// arbitrary, unregistered path is rejected — the terminating panic matched by the
// // Error: directive. (This replaces the legacy allowed-impls "unallowed impl"
// test, whose allowlist model was removed.)

import (
	"testing"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const (
	adminAddr        = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	unregisteredPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v99"
)

func main(cur realm) {
	println("[SCENARIO] 1. The admin installs an impl at an unregistered path -> rejected")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), unregisteredPath)
}

// Output:
// [SCENARIO] 1. The admin installs an impl at an unregistered path -> rejected

// Error:
// impl constructor not found
