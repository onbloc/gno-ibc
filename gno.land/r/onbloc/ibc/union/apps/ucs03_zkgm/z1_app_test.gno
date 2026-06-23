package zkgm

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

// z1_app_test covers app.gno's receiver surface: every callback delegates to the
// installed impl, and the pause gate blocks all callbacks including channel
// handshake. Version enforcement now lives in the impl (v1/impl_test), and the
// caller gate is covered by z2.

func TestAppDelegatesAllReceiversToImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Callbacks are gated to the core caller, so impersonate core.
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	AsIBCApp().OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	AsIBCApp().OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))
	AsIBCApp().OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer"))
	AsIBCApp().OnChannelOpenConfirm(cross(cur), 2, address("g1relayer"))
	res := AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)

	if !d.openInitCalled || !d.openTryCalled || !d.openAckCalled || !d.openConfirmCalled {
		t.Fatal("channel callbacks must delegate to impl")
	}
	if !d.recvCalled || !d.ackCalled || !d.timeoutCalled || !d.intentRecvCalled {
		t.Fatal("packet callbacks must delegate to impl")
	}
	if d.lastCounterpartyVer != Version {
		t.Fatal("counterparty version must be threaded to impl")
	}
	if res.Status != types.PacketStatusSuccess || len(res.Acknowledgement) == 0 {
		t.Fatal("recv result must come from impl")
	}

	// Close callbacks panic with "the show must go on"
	uassert.AbortsContains(t, cur, "the show must go on", func() {
		(&App{}).OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	})
	uassert.AbortsContains(t, cur, "the show must go on", func() {
		(&App{}).OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	})
}

func TestAppPausedBlocksAllCallbacks(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d
	paused = true
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Pause check runs after caller gate, so impersonate core
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// Channel handshake callbacks are blocked by pause
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer"))
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenConfirm(cross(cur), 2, address("g1relayer"))
	})

	// Close callbacks are blocked by pause before "the show must go on"
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	})

	// Packet callbacks are blocked by pause
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})

	// Verify no delegation happened
	if d.openInitCalled || d.openTryCalled || d.openAckCalled || d.openConfirmCalled || d.closeInitCalled || d.closeConfirmCalled || d.recvCalled || d.ackCalled || d.timeoutCalled {
		t.Fatal("paused must block all delegation")
	}
	paused = false
}
