// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/access
package access

// grant_relayer_role_filetest is the NORMAL-path access scenario. The baked-in
// admin (DefaultAdminAddress, which holds AdminRole from the access realm's init)
// grants the RELAYER role to a fresh account. The account moves from unauthorized
// to authorized for the relayer-gated core selectors — verified as a before/after
// authorization diff, the access-control analogue of a balance diff.

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
)

func main(cur realm) {
	println("[SCENARIO] 1. Genesis: admin holds AdminRole, relayer account holds nothing")
	showAuthorization()
	println("[EXPECTED] relayer should NOT be authorized yet (no RelayerRole)")
	println("")

	println("[SCENARIO] 2. Admin grants the RELAYER role to the relayer account")
	grantRelayer(cur)
	println("")

	println("[SCENARIO] 3. Relayer is now authorized for relayer-gated core selectors")
	showAuthorization()
	println("[EXPECTED] relayer should now be authorized (RelayerRole maps to relayer selectors)")
}

// grantRelayer grants RELAYER to relayerAddr as the admin. Admin authorizes via
// cur.Previous(), so SetRealm(admin) and the cross(cur) call share this frame.
func grantRelayer(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	newMember := access.GrantRole(cross(cur), access.RelayerRole, relayerAddr)
	ufmt.Printf("[INFO] GrantRole returned newMember=%t\n", newMember)
	ufmt.Println("[EXPECTED] newMember should be true (first grant)")
}

// showAuthorization reads (non-crossing) the current role membership and the derived
// authorization for a relayer-gated selector on the core realm.
func showAuthorization() {
	ufmt.Printf("[INFO] admin has AdminRole: %t\n", access.HasRole(manager.AdminRole, adminAddr).IsMember)
	ufmt.Printf("[INFO] relayer has RelayerRole: %t\n", access.HasRole(access.RelayerRole, relayerAddr).IsMember)
	ufmt.Printf("[INFO] relayer authorized for packet_recv on core: %t\n", access.IsAuthorized(access.CoreRealmPath, types.RelayerSelectorPacketRecv, relayerAddr))
}

// Output:
// [SCENARIO] 1. Genesis: admin holds AdminRole, relayer account holds nothing
// [INFO] admin has AdminRole: true
// [INFO] relayer has RelayerRole: false
// [INFO] relayer authorized for packet_recv on core: false
// [EXPECTED] relayer should NOT be authorized yet (no RelayerRole)
//
// [SCENARIO] 2. Admin grants the RELAYER role to the relayer account
// [INFO] GrantRole returned newMember=true
// [EXPECTED] newMember should be true (first grant)
//
// [SCENARIO] 3. Relayer is now authorized for relayer-gated core selectors
// [INFO] admin has AdminRole: true
// [INFO] relayer has RelayerRole: true
// [INFO] relayer authorized for packet_recv on core: true
// [EXPECTED] relayer should now be authorized (RelayerRole maps to relayer selectors)
