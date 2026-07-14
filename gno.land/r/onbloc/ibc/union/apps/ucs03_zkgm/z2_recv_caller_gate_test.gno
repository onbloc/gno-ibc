package ucs03_zkgm

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
// ephemeral `maketx run` frame with an empty PkgPath -- must be rejected
// (assertIsCoreRealm). Otherwise a caller could skip core's proof verification and
// receipt recording and jump directly into impl recv -> mint/escrow without proof.
//
// testing.SetRealm changes the current frame only; each test calls it inline.
// setupGateImpl installs a no-op impl so a permitted caller reaches the end of
// the callback without aborting.

func setupGateImpl(cur realm) types.Packet {
	resetZkgmForTest(cur)
	currentImpl = &dummyImpl{}
	paused = false
	return core.NewPacket(1, 2, []byte("data"), 0)
}

func TestRecvGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, ErrNotCoreRealm, func() {
		(&App{}).OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	})
}

func TestIntentRecvGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, ErrNotCoreRealm, func() {
		(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	})
}

func TestAckGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, ErrNotCoreRealm, func() {
		(&App{}).OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})
}

func TestTimeoutGateRejectsEphemeralCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
	uassert.AbortsContains(t, cur, ErrNotCoreRealm, func() {
		(&App{}).OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})
}

func TestRecvGateRejectsProxyCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
	uassert.AbortsContains(t, cur, ErrNotCoreRealm, func() {
		(&App{}).OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	})
}

func TestAckGateRejectsProxyCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
	uassert.AbortsContains(t, cur, ErrNotCoreRealm, func() {
		(&App{}).OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})
}

func TestTimeoutGateRejectsProxyCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
	uassert.AbortsContains(t, cur, ErrNotCoreRealm, func() {
		(&App{}).OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})
}

func TestRecvGateAllowsCoreCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	uassert.NotAborts(t, cur, func() {
		(&App{}).OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
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
		(&App{}).OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})
}

func TestTimeoutGateAllowsCoreCaller(cur realm, t *testing.T) {
	packet := setupGateImpl(cur)
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	uassert.NotAborts(t, cur, func() {
		(&App{}).OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})
}
