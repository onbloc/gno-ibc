// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/access
package access

// role_grant_rejected_unauthorized_filetest is the EXCEPTION-path access scenario. Only
// the admin of a role may grant it; a non-admin account is not an admin of
// RelayerRole, so its grant attempt is rejected. The rejection is the terminating
// panic of main, matched by the // Error: directive (the repo's convention for
// expected-panic filetests — recover does not catch panics across cross(cur)).

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"

	"gno.land/r/onbloc/ibc/union/access"
)

const (
	relayerAddr  = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	nonAdminAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu") // holds no role
)

func main(cur realm) {
	println("[SCENARIO] 1. A non-admin account cannot administer RelayerRole")
	ufmt.Printf("[INFO] non-admin can admin RelayerRole: %t\n", access.CanAdminRole(access.RelayerRole, nonAdminAddr).Immediate)
	ufmt.Println("[EXPECTED] non-admin should NOT be able to administer RelayerRole")
	println("")

	println("[SCENARIO] 2. The non-admin attempts to grant RELAYER -> rejected")
	testing.SetRealm(testing.NewUserRealm(nonAdminAddr))
	access.GrantRole(cross(cur), access.RelayerRole, relayerAddr)
}

// Output:
// [SCENARIO] 1. A non-admin account cannot administer RelayerRole
// [INFO] non-admin can admin RelayerRole: false
// [EXPECTED] non-admin should NOT be able to administer RelayerRole
//
// [SCENARIO] 2. The non-admin attempts to grant RELAYER -> rejected

// Error:
// access manager unauthorized account: g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu must have role 0
