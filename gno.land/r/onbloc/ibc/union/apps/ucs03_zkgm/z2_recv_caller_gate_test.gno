package zkgm

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

// Packet callbacks must only be entered through the IBC core realm, so
// cur.Previous() must resolve to core.PacketRecv/Acknowledgement/Timeout's
// caller context. Any other caller -- a deployed realm, the proxy realm, or an
// ephemeral `maketx run` frame with an empty PkgPath -- must be rejected.
// Otherwise a caller could skip core's proof verification and receipt recording
// and jump directly into impl.Recv -> executeTokenOrderV2, minting vouchers or
// releasing escrow without proof.
//
// testing.SetRealm changes the current frame only. Each test therefore calls it
// inline; a helper would set its own frame and lose the value on return. The
// following crossing call into App then makes cur.Previous() resolve to:
//   NewUserRealm(addr) -> ""    (ephemeral / maketx run)
//   NewCodeRealm(proxy) -> proxy
//   NewCodeRealm(core)  -> core (the only legitimate caller)
//
// setupGateImpl installs a no-op implementation so a permitted caller reaches
// the end of the callback without aborting.

const coreRealmPath = "gno.land/r/onbloc/ibc/union/core"

func setupGateImpl(cur realm) types.Packet {
	resetZkgmForTest()
	impl = &dummyImpl{}
	paused = false
	return core.NewPacket(cross(cur), 1, 2, []byte("data"), 0)
}

// --- ephemeral (`maketx run`, PkgPath "") caller must be rejected ---

func TestRecvGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, "only core can recv", func() {
		AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	})
}

func TestIntentRecvGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, "only core can intent recv", func() {
		(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	})
}

func TestAckGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, "only core can ack", func() {
		AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})
}

func TestTimeoutGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, "only core can timeout", func() {
		AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})
}

// --- proxy realm caller must be rejected (no legitimate self-call path) ---

func TestRecvGateRejectsProxyCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
	uassert.AbortsContains(t, cur, "only core can recv", func() {
		AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	})
}

func TestIntentRecvGateRejectsProxyCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
	uassert.AbortsContains(t, cur, "only core can intent recv", func() {
		(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	})
}

func TestAckGateRejectsProxyCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
	uassert.AbortsContains(t, cur, "only core can ack", func() {
		AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})
}

func TestTimeoutGateRejectsProxyCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
	uassert.AbortsContains(t, cur, "only core can timeout", func() {
		AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})
}

// --- core caller passes the gate (positive control, all four callbacks) ---

func TestRecvGateAllowsCoreCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	uassert.NotAborts(t, cur, func() {
		AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	})
}

func TestIntentRecvGateAllowsCoreCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	uassert.NotAborts(t, cur, func() {
		(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	})
}

func TestAckGateAllowsCoreCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	uassert.NotAborts(t, cur, func() {
		AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})
}

func TestTimeoutGateAllowsCoreCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	uassert.NotAborts(t, cur, func() {
		AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})
}
