// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/access
package access

// Regression demo: SetGrantDelay used to overwrite a role's grant delay
// immediately, letting an admin shrink an observation window and grant a
// role in the same block. It now schedules the change behind a setback
// (manager.MinSetback / Delay.WithUpdate), so a same-block grant still uses
// the delay that was actually active.

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

	oneDaySeconds    = uint32(24 * 60 * 60)
	blocksPerDay     = int64(oneDaySeconds) / 5      // 5s per block
	blocksPerSetback = int64(manager.MinSetback) / 5 // manager.MinSetback is 5 days
)

func main(cur realm) {
	println("[SCENARIO] 1. Admin schedules a 1-day grant delay on RelayerRole")
	setGrantDelay(cur, oneDaySeconds)
	showGrantDelay()
	ufmt.Println("[EXPECTED] the new delay is scheduled, not active yet")
	println("")

	println("[SCENARIO] 2. Advance the chain past the setback: the 1-day delay is now active")
	testing.SkipHeights(blocksPerSetback)
	showGrantDelay()
	ufmt.Println("[EXPECTED] the scheduled delay is now the active grant delay")
	println("")

	println("[SCENARIO] 3. Admin tries to shrink the delay to 0 and grants the role in the same block")
	setGrantDelay(cur, 0)
	grantRelayer(cur)
	showAuthorization()
	ufmt.Println("[EXPECTED] relayer should NOT be authorized yet: the shrink attempt hasn't taken effect, so the grant still used the 1-day delay that was actually active")
	println("")

	println("[SCENARIO] 4. Advance the chain past the 1-day delay that was active at grant time")
	testing.SkipHeights(blocksPerDay)
	showAuthorization()
	ufmt.Println("[EXPECTED] relayer is now authorized, exactly one day after the grant -- the shrink attempt never shortened the observation window")
}

// setGrantDelay configures the delay as the admin. Admin authorizes via
// cur.Previous(), so SetRealm(admin) and the cross(cur) call share this frame.
func setGrantDelay(cur realm, newDelay uint32) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	access.SetGrantDelay(cross(cur), access.RelayerRole, newDelay)
}

func grantRelayer(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	newMember := access.GrantRole(cross(cur), access.RelayerRole, relayerAddr)
	ufmt.Printf("[INFO] GrantRole returned newMember=%t\n", newMember)
}

// showGrantDelay reads the grant delay currently in effect for RelayerRole.
func showGrantDelay() {
	ufmt.Printf("[INFO] RelayerRole grant delay in effect: %d\n", access.GetRoleGrantDelay(access.RelayerRole))
}

// showAuthorization reads (non-crossing) the current role membership and the derived
// authorization for a relayer-gated selector on the core realm.
func showAuthorization() {
	ufmt.Printf("[INFO] relayer has RelayerRole: %t\n", access.HasRole(access.RelayerRole, relayerAddr).IsMember)
	ufmt.Printf("[INFO] relayer authorized for packet_recv on core: %t\n", access.IsAuthorized(access.CoreRealmPath, types.RelayerSelectorPacketRecv, relayerAddr))
}

// Output:
// [SCENARIO] 1. Admin schedules a 1-day grant delay on RelayerRole
// [INFO] RelayerRole grant delay in effect: 0
// [EXPECTED] the new delay is scheduled, not active yet
//
// [SCENARIO] 2. Advance the chain past the setback: the 1-day delay is now active
// [INFO] RelayerRole grant delay in effect: 86400
// [EXPECTED] the scheduled delay is now the active grant delay
//
// [SCENARIO] 3. Admin tries to shrink the delay to 0 and grants the role in the same block
// [INFO] GrantRole returned newMember=true
// [INFO] relayer has RelayerRole: false
// [INFO] relayer authorized for packet_recv on core: false
// [EXPECTED] relayer should NOT be authorized yet: the shrink attempt hasn't taken effect, so the grant still used the 1-day delay that was actually active
//
// [SCENARIO] 4. Advance the chain past the 1-day delay that was active at grant time
// [INFO] relayer has RelayerRole: true
// [INFO] relayer authorized for packet_recv on core: true
// [EXPECTED] relayer is now authorized, exactly one day after the grant -- the shrink attempt never shortened the observation window
