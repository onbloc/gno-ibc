package zkgm

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// Channel handshake callbacks must be entered through the IBC core realm. The
// gate (assertIsIBCHost) runs before any delegation, preserving the
// core-to-app security boundary. The closures are defined in this frame so they
// preserve the testing.SetRealm context used by cur.Previous().

type channelGate struct {
	action string
	invoke func()
}

func setupChannelGate() {
	resetZkgmForTest()
	impl = &dummyImpl{}
	paused = false
}

func TestChannelGateCallerAuthorization(cur realm, t *testing.T) {
	gates := []channelGate{
		{"channel open init", func() { AsIBCApp().OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer")) }},
		{"channel open try", func() { AsIBCApp().OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer")) }},
		{"channel open ack", func() { AsIBCApp().OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer")) }},
		{"channel open confirm", func() { AsIBCApp().OnChannelOpenConfirm(cross(cur), 2, address("g1relayer")) }},
		{"channel close init", func() { AsIBCApp().OnChannelCloseInit(cross(cur), 2, address("g1relayer")) }},
		{"channel close confirm", func() { AsIBCApp().OnChannelCloseConfirm(cross(cur), 2, address("g1relayer")) }},
	}

	// An ephemeral (`maketx run`, PkgPath "") caller must be rejected.
	for _, g := range gates {
		setupChannelGate()
		testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
		uassert.AbortsContains(t, cur, "zkgm: ibc host only", g.invoke)
	}

	// The proxy realm must be rejected: there is no legitimate self-call path.
	for _, g := range gates {
		setupChannelGate()
		testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
		uassert.AbortsContains(t, cur, "zkgm: ibc host only", g.invoke)
	}

	// The core realm passes the gate (positive control); the dummy impl records
	// the delegated call. Channel close is rejected by the real impl, but the
	// dummy records it, so the gate itself is what we assert here.
	for _, g := range gates {
		setupChannelGate()
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		uassert.NotAborts(t, cur, g.invoke)
	}
}
