// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/pause
package pause

// pause_denom_authority_by_caller_filetest is the BY-TYPE pause scenario for the
// per-denom pause gate. Like the global switch, PausableDenom is a privileged
// control gated by the access manager on the "pausable_denom" selector (which
// defaults to AdminRole). It contrasts the two caller types: the admin may flip
// the switch for a specific denom (both pause and unpause succeed), while a
// non-admin caller is rejected. The non-admin attempt is the terminating panic,
// matched by // Error:.

import (
	"testing"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

const (
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5") // holds AdminRole
	nonAdminAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu") // holds no role

	targetDenom = "ugnot"
)

func main(cur realm) {
	println("[SCENARIO] 1. ADMIN: the admin may pause and unpause a specific denom")
	pauseDenomAsAdmin(cur)
	println("[EXPECTED] both pause and unpause should succeed for the admin")
	println("")

	println("[SCENARIO] 2. NON-ADMIN: a non-admin caller may not flip a denom's pause switch -> rejected")
	testing.SetRealm(testing.NewUserRealm(nonAdminAddr))
	zkgm.PausableDenom(cross(cur), targetDenom, true)
}

// pauseDenomAsAdmin flips the switch on and back off for targetDenom as the
// admin. SetRealm(admin) and the cross(cur) calls share this frame so the admin
// is the authorized caller.
func pauseDenomAsAdmin(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.PausableDenom(cross(cur), targetDenom, true)
	println("[INFO] admin paused " + targetDenom)
	zkgm.PausableDenom(cross(cur), targetDenom, false)
	println("[INFO] admin unpaused " + targetDenom)
}

// Output:
// [SCENARIO] 1. ADMIN: the admin may pause and unpause a specific denom
// [INFO] admin paused ugnot
// [INFO] admin unpaused ugnot
// [EXPECTED] both pause and unpause should succeed for the admin
//
// [SCENARIO] 2. NON-ADMIN: a non-admin caller may not flip a denom's pause switch -> rejected

// Error:
// access manager unauthorized call: g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu is not authorized to call pausable_denom on gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
