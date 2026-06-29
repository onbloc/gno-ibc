// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/app
package app

// reject_duplicate_app_registration_filetest is the EXCEPTION-path app scenario. A
// port routes to exactly one IBC app, so registering a second app at a port that is
// already bound is rejected. The zkgm app binds at its proxy port during bootstrap;
// a second RegisterCoreApp for the same port is the terminating panic, matched by
// the // Error: directive.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap core+zkgm and register the zkgm app at its port")
	bootstrap(cur)
	ufmt.Printf("[INFO] zkgm app bound at its port: %t\n", core.HasApp([]byte(zkgm.ProxyPkgPath())))
	ufmt.Println("[EXPECTED] the zkgm app should be registered at its proxy port")
	println("")

	println("[SCENARIO] 2. Registering a second app at the same port -> rejected")
	zkgm.RegisterCoreApp(cross(cur))
}

// bootstrap installs the core/zkgm impls and registers the zkgm app once. UpdateImpl
// is admin-gated, so SetRealm(admin) and the cross(cur) calls share this frame.
func bootstrap(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.RegisterCoreApp(cross(cur))
}

// Output:
// [SCENARIO] 1. Bootstrap core+zkgm and register the zkgm app at its port
// [INFO] zkgm app bound at its port: true
// [EXPECTED] the zkgm app should be registered at its proxy port
//
// [SCENARIO] 2. Registering a second app at the same port -> rejected

// Error:
// port gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm already registered
