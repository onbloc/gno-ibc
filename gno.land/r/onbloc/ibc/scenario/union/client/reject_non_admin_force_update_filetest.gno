// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// reject_non_admin_force_update_filetest is the EXCEPTION-path client scenario for
// the force-update authorization boundary (S-6.4). ForceUpdateClient bypasses header
// verification — it can rewrite a client's state directly — so it is the emergency
// recovery lever and must be admin-only. It is gated by the access manager on the
// "force_update_client" selector (which defaults to AdminRole, not the relayer set),
// so a non-admin caller is rejected. This is the boundary between emergency recovery
// (admin) and an attacker injecting an arbitrary consensus root.

import (
	"chain"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	nonAdminAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu") // holds no role
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap core and create a client")
	clientId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. A non-admin attempts ForceUpdateClient -> rejected")
	testing.SetRealm(testing.NewUserRealm(nonAdminAddr))
	core.ForceUpdateClient(cross(cur), types.NewMsgForceUpdateClient(clientId, nil, nil))
}

func bootstrap(cur realm) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPath))

	mocklc.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mocklc.MockClientType, nil, nil))
	return types.ClientId(1)
}

// Output:
// [SCENARIO] 1. Bootstrap core and create a client
//
// [SCENARIO] 2. A non-admin attempts ForceUpdateClient -> rejected

// Error:
// access manager unauthorized call: g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu is not authorized to call force_update_client on gno.land/r/onbloc/ibc/union/core
