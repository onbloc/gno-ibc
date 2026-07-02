// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/access
package access

// reject_renounce_for_other_account_filetest is the EXCEPTION-path access
// scenario for renounce confirmation. A role member may renounce only for its own
// address; confirming a different account must fail before the role is removed.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"

	"gno.land/r/onbloc/ibc/union/access"
)

const (
	renounceAdmin  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	renounceMember = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	renounceOther  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
)

func main(cur realm) {
	println("[SCENARIO] 1. Admin grants RELAYER to the member")
	testing.SetRealm(testing.NewUserRealm(renounceAdmin))
	access.GrantRole(cross(cur), access.RelayerRole, renounceMember)
	ufmt.Printf("[INFO] member has RelayerRole after grant: %t\n", access.HasRole(access.RelayerRole, renounceMember).IsMember)
	println("[EXPECTED] member should hold RelayerRole before renounce")
	println("")

	println("[SCENARIO] 2. Member tries to renounce with a different callerConfirmation -> rejected")
	testing.SetRealm(testing.NewUserRealm(renounceMember))
	access.RenounceRole(cross(cur), access.RelayerRole, renounceOther)
}

// Output:
// [SCENARIO] 1. Admin grants RELAYER to the member
// [INFO] member has RelayerRole after grant: true
// [EXPECTED] member should hold RelayerRole before renounce
//
// [SCENARIO] 2. Member tries to renounce with a different callerConfirmation -> rejected

// Error:
// access manager bad confirmation
