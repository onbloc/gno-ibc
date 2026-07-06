// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/access
package access

// role_lifecycle_by_operation_filetest is the BY-TYPE access scenario. It walks the
// three distinct role-membership operations — GRANT (admin adds), REVOKE (admin
// removes), RENOUNCE (member removes itself) — and after each one reports the
// member's RelayerRole membership so every transition is verified as a diff.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"

	"gno.land/r/onbloc/ibc/union/access"
)

const (
	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5") // baked-in admin (AdminRole)
	memberAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. GRANT: admin adds RELAYER to the member")
	grant(cur)
	report("after grant")
	println("[EXPECTED] member should now hold RelayerRole")
	println("")

	println("[SCENARIO] 2. REVOKE: admin removes RELAYER from the member")
	revoke(cur)
	report("after revoke")
	println("[EXPECTED] member should no longer hold RelayerRole")
	println("")

	println("[SCENARIO] 3. RENOUNCE: member is re-granted, then drops RELAYER itself")
	grant(cur)
	renounce(cur)
	report("after renounce")
	println("[EXPECTED] member should no longer hold RelayerRole (self-renounced)")
}

func grant(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	ufmt.Printf("[INFO] GrantRole newMember=%t\n", access.GrantRole(cross(cur), access.RelayerRole, memberAddr))
}

func revoke(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	ufmt.Printf("[INFO] RevokeRole revoked=%t\n", access.RevokeRole(cross(cur), access.RelayerRole, memberAddr))
}

// renounce is driven by the member itself, confirming with its own address.
func renounce(cur realm) {
	testing.SetRealm(testing.NewUserRealm(memberAddr))
	ufmt.Printf("[INFO] RenounceRole revoked=%t\n", access.RenounceRole(cross(cur), access.RelayerRole, memberAddr))
}

func report(label string) {
	ufmt.Printf("[INFO] member has RelayerRole %s: %t\n", label, access.HasRole(access.RelayerRole, memberAddr).IsMember)
}

// Output:
// [SCENARIO] 1. GRANT: admin adds RELAYER to the member
// [INFO] GrantRole newMember=true
// [INFO] member has RelayerRole after grant: true
// [EXPECTED] member should now hold RelayerRole
//
// [SCENARIO] 2. REVOKE: admin removes RELAYER from the member
// [INFO] RevokeRole revoked=true
// [INFO] member has RelayerRole after revoke: false
// [EXPECTED] member should no longer hold RelayerRole
//
// [SCENARIO] 3. RENOUNCE: member is re-granted, then drops RELAYER itself
// [INFO] GrantRole newMember=true
// [INFO] RenounceRole revoked=true
// [INFO] member has RelayerRole after renounce: false
// [EXPECTED] member should no longer hold RelayerRole (self-renounced)
