// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/access
package access

// Regression: SetTargetClosed used to infer target from the caller's own
// path, so an admin calling from a different realm to close core would
// silently close the caller instead. This closes core by its explicit path
// from a distinct calling realm and checks only core becomes unreachable.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
)

const adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5") // baked-in DefaultAdminAddress (holds AdminRole)

var relayerSelector = types.RelayerSelectors()[0]

func main(cur realm) {
	println("[SCENARIO] 1. Genesis: core target is open, relayer holds RELAYER role")
	grantRelayer(cur)
	report()
	println("[EXPECTED] core authorized, core not closed, caller's own path not closed")
	println("")

	println("[SCENARIO] 2. Admin closes core by its explicit path from a different calling realm")
	closeCore(cur)
	report()
	println("[EXPECTED] core now unauthorized and closed; caller's own path must remain open")
}

func grantRelayer(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
}

func closeCore(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	access.SetTargetClosed(cross(cur), access.CoreRealmPath, true)
}

func report() {
	ufmt.Printf("[INFO] admin authorized for core relayer selector: %t\n", access.CanCall(access.CoreRealmPath, relayerSelector, adminAddr).Immediate)
	ufmt.Printf("[INFO] core target closed: %t\n", access.IsTargetClosed(access.CoreRealmPath))
	ufmt.Printf("[INFO] caller's own path closed: %t\n", access.IsTargetClosed("gno.land/r/onbloc/ibc/scenario/union/access"))
}

// Output:
// [SCENARIO] 1. Genesis: core target is open, relayer holds RELAYER role
// [INFO] admin authorized for core relayer selector: true
// [INFO] core target closed: false
// [INFO] caller's own path closed: false
// [EXPECTED] core authorized, core not closed, caller's own path not closed
//
// [SCENARIO] 2. Admin closes core by its explicit path from a different calling realm
// [INFO] admin authorized for core relayer selector: false
// [INFO] core target closed: true
// [INFO] caller's own path closed: false
// [EXPECTED] core now unauthorized and closed; caller's own path must remain open
