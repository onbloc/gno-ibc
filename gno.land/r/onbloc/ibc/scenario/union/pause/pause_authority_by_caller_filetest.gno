// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/pause
package pause

// pause_authority_by_caller_filetest is the BY-TYPE pause scenario. The pause switch
// is a privileged control, gated by the access manager on the "pausable" selector
// (which defaults to AdminRole). It contrasts the two caller types: the admin may
// flip the switch (both pause and unpause succeed), while a non-admin caller is
// rejected. The non-admin attempt is the terminating panic, matched by // Error:.

import (
	"testing"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

const (
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5") // holds AdminRole
	nonAdminAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu") // holds no role
)

func main(cur realm) {
	println("[SCENARIO] 1. ADMIN: the admin may pause and unpause the app")
	pauseAsAdmin(cur)
	println("[EXPECTED] both pause and unpause should succeed for the admin")
	println("")

	println("[SCENARIO] 2. NON-ADMIN: a non-admin caller may not flip the pause switch -> rejected")
	testing.SetRealm(testing.NewUserRealm(nonAdminAddr))
	zkgm.Pausable(cross(cur), true)
}

// pauseAsAdmin flips the switch on and back off as the admin. SetRealm(admin) and the
// cross(cur) calls share this frame so the admin is the authorized caller.
func pauseAsAdmin(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.Pausable(cross(cur), true)
	println("[INFO] admin paused the app")
	zkgm.Pausable(cross(cur), false)
	println("[INFO] admin unpaused the app")
}

// Output:
// [SCENARIO] 1. ADMIN: the admin may pause and unpause the app
// [INFO] admin paused the app
// [INFO] admin unpaused the app
// [EXPECTED] both pause and unpause should succeed for the admin
//
// [SCENARIO] 2. NON-ADMIN: a non-admin caller may not flip the pause switch -> rejected

// Error:
// access manager unauthorized call: g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu is not authorized to call pausable on gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
