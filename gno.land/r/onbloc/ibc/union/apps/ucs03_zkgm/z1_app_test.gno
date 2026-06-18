package zkgm

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

// z1_app_test covers app.gno's receiver surface: every callback delegates to the
// installed impl, and the pause gate blocks the packet callbacks while leaving
// channel handshake available. Version enforcement now lives in the impl
// (v1/impl_test), and the caller gate is covered by z2/z3.

func TestAppDelegatesAllReceiversToImpl(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	packet := core.NewPacket(cross(cur), 1, 2, []byte("data"), 0)

	// Callbacks are gated to the core caller, so impersonate core.
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	AsIBCApp().OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	AsIBCApp().OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))
	AsIBCApp().OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer"))
	AsIBCApp().OnChannelOpenConfirm(cross(cur), 2, address("g1relayer"))
	AsIBCApp().OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	AsIBCApp().OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	res := AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	AsIBCApp().OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	AsIBCApp().OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)

	if !d.openInitCalled || !d.openTryCalled || !d.openAckCalled || !d.openConfirmCalled || !d.closeInitCalled || !d.closeConfirmCalled {
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
}

func TestAppPausedBlocksPacketCallbacksNotHandshake(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true
	packet := core.NewPacket(cross(cur), 1, 2, []byte("data"), 0)

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// Handshake remains available while paused.
	AsIBCApp().OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	if !d.openInitCalled {
		t.Fatal("paused must not block channel handshake")
	}

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

	if d.recvCalled || d.ackCalled || d.timeoutCalled {
		t.Fatal("paused must block packet-callback delegation")
	}
	paused = false
}
