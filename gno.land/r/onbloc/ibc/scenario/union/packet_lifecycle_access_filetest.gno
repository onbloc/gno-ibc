// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// packet_lifecycle_access_filetest documents the operational access story for
// recv/ack/timeout packet handling: relayers are required today, full relayer
// loss stops all packet progress, admin regrant restores it, and a future
// timeout-only PublicRole escape hatch would let arbitrary users reach the
// timeout implementation path without opening recv/ack/intent recv.

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/access/manager"
	types "gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
)

var (
	packetAccessAdmin    = access.DefaultAdminAddress
	packetAccessRelayerA = testutils.TestAddress("packet-relayer-a")
	packetAccessRelayerB = testutils.TestAddress("packet-relayer-b")
	packetAccessUser     = testutils.TestAddress("packet-user")
)

func main(cur realm) {
	println("[SCENARIO] Packet lifecycle relayer access and timeout escape hatch")
	println()

	println("[STEP 1] Baseline: packet lifecycle selectors require RelayerRole")
	printSelectorMatrix("baseline_user", packetAccessUser)
	printCallMatrix(cur, "baseline_user_calls", packetAccessUser)
	println("[SUCCESS] ordinary users cannot recv, ack, timeout, or intent-recv")
	println()

	println("[STEP 2] Grant two independent relayers")
	testing.SetRealm(testing.NewUserRealm(packetAccessAdmin))
	access.GrantRole(cross(cur), access.RelayerRole, packetAccessRelayerA)
	access.GrantRole(cross(cur), access.RelayerRole, packetAccessRelayerB)
	printRelayerHealth("relayer_a_after_grant", packetAccessRelayerA)
	printRelayerHealth("relayer_b_after_grant", packetAccessRelayerB)
	printCallMatrix(cur, "relayer_a_calls", packetAccessRelayerA)
	println("[SUCCESS] either relayer can pass the access gate")
	println()

	println("[STEP 3] Revoke every relayer: user self-rescue is unavailable")
	testing.SetRealm(testing.NewUserRealm(packetAccessAdmin))
	access.RevokeRole(cross(cur), access.RelayerRole, packetAccessRelayerA)
	access.RevokeRole(cross(cur), access.RelayerRole, packetAccessRelayerB)
	printRelayerHealth("relayer_a_after_revoke", packetAccessRelayerA)
	printRelayerHealth("relayer_b_after_revoke", packetAccessRelayerB)
	printSelectorMatrix("user_after_relayer_loss", packetAccessUser)
	printCallMatrix(cur, "user_after_relayer_loss_calls", packetAccessUser)
	println("[SUCCESS] recv/ack/timeout all require admin to restore a relayer")
	println()

	println("[STEP 4] Admin emergency regrant restores liveness")
	testing.SetRealm(testing.NewUserRealm(packetAccessAdmin))
	access.GrantRole(cross(cur), access.RelayerRole, packetAccessRelayerB)
	printRelayerHealth("relayer_b_after_regrant", packetAccessRelayerB)
	printCallMatrix(cur, "relayer_b_after_regrant_calls", packetAccessRelayerB)
	println("[SUCCESS] operational recovery requires admin action under current policy")
	println()

	println("[STEP 5] Future policy: open only timeout to PublicRole")
	// SetFunctionRole configures the previous realm's target. Grant core's code
	// realm temporary admin authority, then make the previous realm look like
	// core so only core's packet_timeout selector is opened.
	coreRealm := testing.NewCodeRealm(access.CoreRealmPath)
	testing.SetRealm(testing.NewUserRealm(packetAccessAdmin))
	access.GrantRole(cross(cur), manager.AdminRole, coreRealm.Address())
	testing.SetRealm(coreRealm)
	access.SetFunctionRole(cross(cur), types.RelayerSelectorPacketTimeout, manager.PublicRole)
	printSelectorMatrix("user_after_timeout_public", packetAccessUser)
	printCallMatrix(cur, "user_after_timeout_public_calls", packetAccessUser)
	println("[SUCCESS] timeout can be user-triggered while recv/ack/intent remain relayer-only")
}

func printRelayerHealth(label string, account address) {
	hasRelayer := access.HasRole(access.RelayerRole, account).IsMember
	canRecv := access.CanCall(access.CoreRealmPath, types.RelayerSelectorPacketRecv, account).Immediate
	canAck := access.CanCall(access.CoreRealmPath, types.RelayerSelectorPacketAck, account).Immediate
	canTimeout := access.CanCall(access.CoreRealmPath, types.RelayerSelectorPacketTimeout, account).Immediate
	ufmt.Printf("[INFO] %s address=%s has_relayer=%t can_recv=%t can_ack=%t can_timeout=%t\n", label, account.String(), hasRelayer, canRecv, canAck, canTimeout)
}

func printSelectorMatrix(label string, account address) {
	ufmt.Printf("[INFO] %s recv_authorized=%t intent_authorized=%t ack_authorized=%t timeout_authorized=%t timeout_immediate=%t\n",
		label,
		access.CanCall(access.CoreRealmPath, types.RelayerSelectorPacketRecv, account).Authorized,
		access.CanCall(access.CoreRealmPath, types.RelayerSelectorIntentPacketRecv, account).Authorized,
		access.CanCall(access.CoreRealmPath, types.RelayerSelectorPacketAck, account).Authorized,
		access.CanCall(access.CoreRealmPath, types.RelayerSelectorPacketTimeout, account).Authorized,
		access.CanCall(access.CoreRealmPath, types.RelayerSelectorPacketTimeout, account).Immediate,
	)
}

func printCallMatrix(cur realm, label string, caller address) {
	testing.SetRealm(testing.NewUserRealm(caller))

	recvErr := packetAccessAbortMessage(func() {
		core.PacketRecv(cross(cur), types.MsgPacketRecv{})
	})
	intentErr := packetAccessAbortMessage(func() {
		core.IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{})
	})
	ackErr := packetAccessAbortMessage(func() {
		core.PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{})
	})
	timeoutErr := packetAccessAbortMessage(func() {
		core.PacketTimeout(cross(cur), types.MsgPacketTimeout{})
	})

	ufmt.Printf("[INFO] %s recv_gate=%s intent_gate=%s ack_gate=%s timeout_gate=%s\n",
		label,
		packetAccessGateResult(recvErr),
		packetAccessGateResult(intentErr),
		packetAccessGateResult(ackErr),
		packetAccessGateResult(timeoutErr),
	)
}

func packetAccessGateResult(err string) string {
	if strings.Contains(err, access.ErrAccessManagerUnauthorizedCall) {
		return "unauthorized"
	}
	if strings.Contains(err, "implementation not installed") {
		return "impl_boundary"
	}
	if err == "" {
		return "ok"
	}
	return "other_abort"
}

func packetAccessAbortMessage(fn func()) string {
	p := revive(fn)
	if p == nil {
		return ""
	}
	return ufmt.Sprintf("%v", p)
}

// Output:
// [SCENARIO] Packet lifecycle relayer access and timeout escape hatch
//
// [STEP 1] Baseline: packet lifecycle selectors require RelayerRole
// [INFO] baseline_user recv_authorized=false intent_authorized=false ack_authorized=false timeout_authorized=false timeout_immediate=false
// [INFO] baseline_user_calls recv_gate=unauthorized intent_gate=unauthorized ack_gate=unauthorized timeout_gate=unauthorized
// [SUCCESS] ordinary users cannot recv, ack, timeout, or intent-recv
//
// [STEP 2] Grant two independent relayers
// [INFO] relayer_a_after_grant address=g1wpskx6m9wskhyetvv9uk2u3dv9047h6l6zjyup has_relayer=true can_recv=true can_ack=true can_timeout=true
// [INFO] relayer_b_after_grant address=g1wpskx6m9wskhyetvv9uk2u3dvf047h6lqttfcz has_relayer=true can_recv=true can_ack=true can_timeout=true
// [INFO] relayer_a_calls recv_gate=impl_boundary intent_gate=impl_boundary ack_gate=impl_boundary timeout_gate=impl_boundary
// [SUCCESS] either relayer can pass the access gate
//
// [STEP 3] Revoke every relayer: user self-rescue is unavailable
// [INFO] relayer_a_after_revoke address=g1wpskx6m9wskhyetvv9uk2u3dv9047h6l6zjyup has_relayer=false can_recv=false can_ack=false can_timeout=false
// [INFO] relayer_b_after_revoke address=g1wpskx6m9wskhyetvv9uk2u3dvf047h6lqttfcz has_relayer=false can_recv=false can_ack=false can_timeout=false
// [INFO] user_after_relayer_loss recv_authorized=false intent_authorized=false ack_authorized=false timeout_authorized=false timeout_immediate=false
// [INFO] user_after_relayer_loss_calls recv_gate=unauthorized intent_gate=unauthorized ack_gate=unauthorized timeout_gate=unauthorized
// [SUCCESS] recv/ack/timeout all require admin to restore a relayer
//
// [STEP 4] Admin emergency regrant restores liveness
// [INFO] relayer_b_after_regrant address=g1wpskx6m9wskhyetvv9uk2u3dvf047h6lqttfcz has_relayer=true can_recv=true can_ack=true can_timeout=true
// [INFO] relayer_b_after_regrant_calls recv_gate=impl_boundary intent_gate=impl_boundary ack_gate=impl_boundary timeout_gate=impl_boundary
// [SUCCESS] operational recovery requires admin action under current policy
//
// [STEP 5] Future policy: open only timeout to PublicRole
// [INFO] user_after_timeout_public recv_authorized=false intent_authorized=false ack_authorized=false timeout_authorized=true timeout_immediate=true
// [INFO] user_after_timeout_public_calls recv_gate=unauthorized intent_gate=unauthorized ack_gate=unauthorized timeout_gate=impl_boundary
// [SUCCESS] timeout can be user-triggered while recv/ack/intent remain relayer-only
