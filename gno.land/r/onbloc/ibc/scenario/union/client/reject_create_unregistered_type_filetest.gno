// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// reject_create_unregistered_type_filetest is the EXCEPTION-path client scenario.
// A client type must be registered before a client of that type can be created.
// The admin is relayer-authorized (so the access gate passes), but no client type
// is registered, so CreateClient is rejected once it reaches the registry lookup.
// The rejection is the terminating panic, matched by the // Error: directive.

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	unregisteredType = types.ClientType("never-registered-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap core and authorize the admin as relayer (no client type registered)")
	bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Creating a client of an unregistered type -> rejected")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(unregisteredType, nil, nil))
}

// bootstrap installs the core impl and grants the admin the relayer role so the
// CreateClient access gate passes and the failure is specifically the missing type.
func bootstrap(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
}

// Output:
// [SCENARIO] 1. Bootstrap core and authorize the admin as relayer (no client type registered)
//
// [SCENARIO] 2. Creating a client of an unregistered type -> rejected

// Error:
// client type not found
