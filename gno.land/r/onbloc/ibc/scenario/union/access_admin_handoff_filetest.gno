// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// access_admin_handoff_filetest follows the Gnoswap scenario style: it drives
// the public access-manager realm through an operational admin handoff, prints
// each actor's authority snapshot, and proves the previous admin cannot keep
// managing relayer access after the handoff.

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/r/onbloc/ibc/union/access"
)

var (
	accessHandoffAdminA   = access.DefaultAdminAddress
	accessHandoffAdminB   = testutils.TestAddress("handoff-admin-b")
	accessHandoffRelayer  = testutils.TestAddress("handoff-relayer")
	accessHandoffOutsider = testutils.TestAddress("handoff-outsider")
)

func main(cur realm) {
	println("[SCENARIO] Access admin handoff A -> B")
	println()

	println("[STEP 1] Verify bootstrap admin state")
	printAdminSnapshot("admin_a_initial", accessHandoffAdminA)
	printAdminSnapshot("admin_b_initial", accessHandoffAdminB)
	printRelayerSnapshot("relayer_initial", accessHandoffRelayer)
	println("[SUCCESS] bootstrap admin owns role management before handoff")
	println()

	println("[STEP 2] Admin A grants AdminRole to Admin B")
	testing.SetRealm(testing.NewUserRealm(accessHandoffAdminA))
	access.GrantRole(cross(cur), manager.AdminRole, accessHandoffAdminB)
	printAdminSnapshot("admin_a_after_grant_b", accessHandoffAdminA)
	printAdminSnapshot("admin_b_after_grant_b", accessHandoffAdminB)
	println("[SUCCESS] Admin B is now an active admin alongside Admin A")
	println()

	println("[STEP 3] Admin B proves authority by granting a relayer")
	testing.SetRealm(testing.NewUserRealm(accessHandoffAdminB))
	access.GrantRole(cross(cur), access.RelayerRole, accessHandoffRelayer)
	printRelayerSnapshot("relayer_after_admin_b_grant", accessHandoffRelayer)
	ufmt.Printf("[INFO] outsider_can_manage_admin_role: %t\n", access.CanAdminRole(manager.AdminRole, accessHandoffOutsider).Immediate)
	println("[SUCCESS] new admin can operate role management")
	println()

	println("[STEP 4] Admin B revokes Admin A")
	access.RevokeRole(cross(cur), manager.AdminRole, accessHandoffAdminA)
	printAdminSnapshot("admin_a_after_revoke", accessHandoffAdminA)
	printAdminSnapshot("admin_b_after_revoke", accessHandoffAdminB)
	println("[SUCCESS] handoff completed; Admin B is the remaining admin")
	println()

	println("[STEP 5] Previous admin can no longer grant relayer access")
	testing.SetRealm(testing.NewUserRealm(accessHandoffAdminA))
	previousAdminErr := accessHandoffAbortMessage(func() {
		access.GrantRole(cross(cur), access.RelayerRole, accessHandoffAdminA)
	})
	ufmt.Printf("[INFO] previous_admin_grant_blocked: %t\n", strings.Contains(previousAdminErr, access.ErrAccessManagerUnauthorizedAccount))
	ufmt.Printf("[INFO] previous_admin_error: %s\n", previousAdminErr)
	printRelayerSnapshot("previous_admin_not_regranted_as_relayer", accessHandoffAdminA)
	println("[SUCCESS] previous admin lost role-management authority")
	println()

	println("[STEP 6] Remaining admin can continue operations")
	testing.SetRealm(testing.NewUserRealm(accessHandoffAdminB))
	access.RevokeRole(cross(cur), access.RelayerRole, accessHandoffRelayer)
	printRelayerSnapshot("relayer_after_cleanup", accessHandoffRelayer)
	println("[SUCCESS] operational cleanup is still available to Admin B")
}

func printAdminSnapshot(label string, account address) {
	hasAdmin := access.HasRole(manager.AdminRole, account).IsMember
	canAdminAdmin := access.CanAdminRole(manager.AdminRole, account)
	canAdminRelayer := access.CanAdminRole(access.RelayerRole, account)
	ufmt.Printf("[INFO] %s address=%s has_admin=%t can_admin_admin=%t can_admin_relayer=%t\n", label, account.String(), hasAdmin, canAdminAdmin.Immediate, canAdminRelayer.Immediate)
}

func printRelayerSnapshot(label string, account address) {
	hasRelayer := access.HasRole(access.RelayerRole, account).IsMember
	canPacketRecv := access.CanCall(access.CoreRealmPath, "packet_recv", account)
	canPacketTimeout := access.CanCall(access.CoreRealmPath, "packet_timeout", account)
	ufmt.Printf("[INFO] %s address=%s has_relayer=%t can_packet_recv=%t can_packet_timeout=%t\n", label, account.String(), hasRelayer, canPacketRecv.Immediate, canPacketTimeout.Immediate)
}

func accessHandoffAbortMessage(fn func()) string {
	p := revive(fn)
	if p == nil {
		return ""
	}
	return ufmt.Sprintf("%v", p)
}

// Output:
// [SCENARIO] Access admin handoff A -> B
//
// [STEP 1] Verify bootstrap admin state
// [INFO] admin_a_initial address=g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5 has_admin=true can_admin_admin=true can_admin_relayer=true
// [INFO] admin_b_initial address=g1dpskuer0venz6ctyd45kuttzta047h6l876qym has_admin=false can_admin_admin=false can_admin_relayer=false
// [INFO] relayer_initial address=g1dpskuer0venz6un9d3shjetjta047h6lylm57v has_relayer=false can_packet_recv=false can_packet_timeout=false
// [SUCCESS] bootstrap admin owns role management before handoff
//
// [STEP 2] Admin A grants AdminRole to Admin B
// [INFO] admin_a_after_grant_b address=g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5 has_admin=true can_admin_admin=true can_admin_relayer=true
// [INFO] admin_b_after_grant_b address=g1dpskuer0venz6ctyd45kuttzta047h6l876qym has_admin=true can_admin_admin=true can_admin_relayer=true
// [SUCCESS] Admin B is now an active admin alongside Admin A
//
// [STEP 3] Admin B proves authority by granting a relayer
// [INFO] relayer_after_admin_b_grant address=g1dpskuer0venz6un9d3shjetjta047h6lylm57v has_relayer=true can_packet_recv=true can_packet_timeout=true
// [INFO] outsider_can_manage_admin_role: false
// [SUCCESS] new admin can operate role management
//
// [STEP 4] Admin B revokes Admin A
// [INFO] admin_a_after_revoke address=g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5 has_admin=false can_admin_admin=false can_admin_relayer=false
// [INFO] admin_b_after_revoke address=g1dpskuer0venz6ctyd45kuttzta047h6l876qym has_admin=true can_admin_admin=true can_admin_relayer=true
// [SUCCESS] handoff completed; Admin B is the remaining admin
//
// [STEP 5] Previous admin can no longer grant relayer access
// [INFO] previous_admin_grant_blocked: true
// [INFO] previous_admin_error: access manager unauthorized account: g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5 must have role 0
// [INFO] previous_admin_not_regranted_as_relayer address=g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5 has_relayer=false can_packet_recv=false can_packet_timeout=false
// [SUCCESS] previous admin lost role-management authority
//
// [STEP 6] Remaining admin can continue operations
// [INFO] relayer_after_cleanup address=g1dpskuer0venz6un9d3shjetjta047h6lylm57v has_relayer=false can_packet_recv=false can_packet_timeout=false
// [SUCCESS] operational cleanup is still available to Admin B
