// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/access
package access

// role_grant_delay_defers_activation_filetest is the NORMAL-path access
// scenario for a delayed grant. The admin configures a grant delay on
// RelayerRole via access.SetGrantDelay, then grants the role to a fresh
// account. Access.isActiveAt (manager/access.gno) only activates a grant once
// the current time reaches Since (the grant time plus the configured delay),
// so the account is NOT yet authorized for relayer-gated core selectors
// immediately after the grant — only once the chain advances past the delay
// does the same account become authorized, with no further action required.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"

	"gno.land/p/onbloc/access/manager"
	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
)

const (
	adminAddr   = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5") // baked-in DefaultAdminAddress (holds AdminRole)
	relayerAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	grantDelaySeconds = manager.Delay(10)
)

func main(cur realm) {
	println("[SCENARIO] 1. Admin sets a 10s grant delay on RelayerRole")
	setGrantDelay(cur)
	println("")

	println("[SCENARIO] 2. Admin grants RelayerRole to a fresh account")
	grantRelayer(cur)
	showAuthorization()
	ufmt.Println("[EXPECTED] relayer should NOT be authorized yet: the grant is pending the delay")
	println("")

	println("[SCENARIO] 3. Advance the chain past the delay: the same grant is now active")
	testing.SkipHeights(3) // 3 blocks * 5s = 15s, past the 10s delay
	showAuthorization()
	ufmt.Println("[EXPECTED] relayer should now be authorized, with no further admin action")
}

// setGrantDelay configures the delay as the admin. Admin authorizes via
// cur.Previous(), so SetRealm(admin) and the cross(cur) call share this frame.
func setGrantDelay(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	access.SetGrantDelay(cross(cur), access.RelayerRole, grantDelaySeconds)
}

func grantRelayer(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	newMember := access.GrantRole(cross(cur), access.RelayerRole, relayerAddr)
	ufmt.Printf("[INFO] GrantRole returned newMember=%t\n", newMember)
}

// showAuthorization reads (non-crossing) the current role membership and the derived
// authorization for a relayer-gated selector on the core realm.
func showAuthorization() {
	ufmt.Printf("[INFO] relayer has RelayerRole: %t\n", access.HasRole(access.RelayerRole, relayerAddr).IsMember)
	ufmt.Printf("[INFO] relayer authorized for packet_recv on core: %t\n", access.IsAuthorized(access.CoreRealmPath, types.RelayerSelectorPacketRecv, relayerAddr))
}

// Output:
// [SCENARIO] 1. Admin sets a 10s grant delay on RelayerRole
//
// [SCENARIO] 2. Admin grants RelayerRole to a fresh account
// [INFO] GrantRole returned newMember=true
// [INFO] relayer has RelayerRole: false
// [INFO] relayer authorized for packet_recv on core: false
// [EXPECTED] relayer should NOT be authorized yet: the grant is pending the delay
//
// [SCENARIO] 3. Advance the chain past the delay: the same grant is now active
// [INFO] relayer has RelayerRole: true
// [INFO] relayer authorized for packet_recv on core: true
// [EXPECTED] relayer should now be authorized, with no further admin action
