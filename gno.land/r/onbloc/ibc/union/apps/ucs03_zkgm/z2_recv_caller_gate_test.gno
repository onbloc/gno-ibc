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
// ephemeral `maketx run` frame with an empty PkgPath -- must be rejected
// (assertIsIBCHost). Otherwise a caller could skip core's proof verification and
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

func TestPacketCallbackCallerGate(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		callback  string
		caller    string
		wantAbort string
	}{
		{"recv rejects ephemeral caller", "recv", "ephemeral", "zkgm: ibc host only"},
		{"intent recv rejects ephemeral caller", "intent_recv", "ephemeral", "zkgm: ibc host only"},
		{"ack rejects ephemeral caller", "ack", "ephemeral", "zkgm: ibc host only"},
		{"timeout rejects ephemeral caller", "timeout", "ephemeral", "zkgm: ibc host only"},
		{"recv rejects proxy caller", "recv", "proxy", "zkgm: ibc host only"},
		{"intent recv rejects proxy caller", "intent_recv", "proxy", "zkgm: ibc host only"},
		{"ack rejects proxy caller", "ack", "proxy", "zkgm: ibc host only"},
		{"timeout rejects proxy caller", "timeout", "proxy", "zkgm: ibc host only"},
		{"recv allows core caller", "recv", "core", ""},
		{"intent recv allows core caller", "intent_recv", "core", ""},
		{"ack allows core caller", "ack", "core", ""},
		{"timeout allows core caller", "timeout", "core", ""},
	}

	for _, tc := range cases {
		packet := setupGateImpl(cur)
		switch tc.caller {
		case "ephemeral":
			testing.SetRealm(testing.NewUserRealm(address(testutils.TestAddress("eoa"))))
		case "proxy":
			testing.SetRealm(testing.NewCodeRealm(proxyPkgPath))
		case "core":
			testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		default:
			t.Fatalf("%s: unknown caller %q", tc.name, tc.caller)
		}

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func() {
				switch tc.callback {
				case "recv":
					AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
				case "intent_recv":
					(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
				case "ack":
					AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
				case "timeout":
					AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
				default:
					t.Fatalf("%s: unknown callback %q", tc.name, tc.callback)
				}
			})
			continue
		}

		uassert.NotAborts(t, cur, func() {
			switch tc.callback {
			case "recv":
				AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
			case "intent_recv":
				(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
			case "ack":
				AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
			case "timeout":
				AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
			default:
				t.Fatalf("%s: unknown callback %q", tc.name, tc.callback)
			}
		})
	}
}
