// Ported from Union CosmWasm tests
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs
package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"

	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/core"
)

// test_on_channel_open_init_ok
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3380-L3402
func TestOnChannelOpenInitOk(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	// Channel callbacks are gated to the core caller, so impersonate core.
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	(&App{}).OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))

	if !d.openInitCalled || d.lastChannelId != 2 {
		t.Fatal("OnChannelOpenInit must delegate to impl")
	}
}

// test_on_channel_open_init_invalid_version
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3405-L3435
func TestOnChannelOpenInitInvalidVersion(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "unsupported channel version", func() {
		(&App{}).OnChannelOpenInit(cross(cur), 1, 2, "im-invalid", address("g1relayer"))
	})

	// impl should not be called for invalid version
	if d.openInitCalled {
		t.Fatal("OnChannelOpenInit must not delegate for invalid version")
	}
}

// test_on_channel_open_init_only_ibc
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3438-L3466
func TestOnChannelOpenInitOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	// Do NOT impersonate core - call from a non-core realm
	uassert.AbortsContains(t, cur, "only core can", func() {
		(&App{}).OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	})

	// impl should not be called when caller is not IBC host
	if d.openInitCalled {
		t.Fatal("OnChannelOpenInit must not delegate for non-IBC caller")
	}
}

// test_on_channel_open_try_ok
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3469-L3492
func TestOnChannelOpenTryOk(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))

	if !d.openTryCalled || d.lastCounterpartyVer != Version {
		t.Fatal("OnChannelOpenTry must delegate with counterparty version")
	}
}

// test_on_channel_open_try_invalid_version
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3495-L3526
func TestOnChannelOpenTryInvalidVersion(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "unsupported channel version", func() {
		(&App{}).OnChannelOpenTry(cross(cur), 1, 2, "im-invalid", Version, address("g1relayer"))
	})

	// impl should not be called for invalid version
	if d.openTryCalled {
		t.Fatal("OnChannelOpenTry must not delegate for invalid version")
	}
}

// test_on_channel_open_try_invalid_counterparty_version
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3529-L3560
func TestOnChannelOpenTryInvalidCounterpartyVersion(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "unsupported channel version", func() {
		(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, "im-invalid", address("g1relayer"))
	})

	// impl should not be called for invalid counterparty version
	if d.openTryCalled {
		t.Fatal("OnChannelOpenTry must not delegate for invalid counterparty version")
	}
}

// test_on_channel_open_try_only_ibc
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3563-L3592
func TestOnChannelOpenTryOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	// Do NOT impersonate core - call from a non-core realm
	uassert.AbortsContains(t, cur, "only core can", func() {
		(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))
	})

	// impl should not be called when caller is not IBC host
	if d.openTryCalled {
		t.Fatal("OnChannelOpenTry must not delegate for non-IBC caller")
	}
}

// test_on_channel_open_ack_and_confirm_noop
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3595-L3640
func TestOnChannelOpenAckAndConfirmNoop(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// OnChannelOpenAck should delegate to impl (no-op in current impl)
	(&App{}).OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer"))
	if !d.openAckCalled {
		t.Fatal("OnChannelOpenAck must delegate to impl")
	}

	// OnChannelOpenConfirm should delegate to impl (no-op in current impl)
	(&App{}).OnChannelOpenConfirm(cross(cur), 2, address("g1relayer"))
	if !d.openConfirmCalled {
		t.Fatal("OnChannelOpenConfirm must delegate to impl")
	}
}

// test_on_channel_close_init_impossible
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3643-L3669
// Union implementation: "the show must go on" error for all close callbacks
func TestOnChannelCloseInitImpossible(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// Union rejects close init with "the show must go on" error
	uassert.AbortsContains(t, cur, "the show must go on", func() {
		(&App{}).OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	})

	// impl should NOT be called - we reject before delegation
	if d.closeInitCalled {
		t.Fatal("OnChannelCloseInit must not delegate - should panic with 'the show must go on'")
	}
}

// test_on_channel_close_init_only_ibc
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3672-L3698
func TestOnChannelCloseInitOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	// Do NOT impersonate core - call from a non-core realm
	// The caller gate runs before the close rejection
	uassert.AbortsContains(t, cur, "only core can", func() {
		(&App{}).OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	})

	// impl should not be called when caller is not IBC host
	if d.closeInitCalled {
		t.Fatal("OnChannelCloseInit must not delegate for non-IBC caller")
	}
}

// test_on_channel_close_confirm_impossible
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3701-L3727
// Union implementation: "the show must go on" error for all close callbacks
func TestOnChannelCloseConfirmImpossible(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// Union rejects close confirm with "the show must go on" error
	uassert.AbortsContains(t, cur, "the show must go on", func() {
		(&App{}).OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	})

	// impl should NOT be called - we reject before delegation
	if d.closeConfirmCalled {
		t.Fatal("OnChannelCloseConfirm must not delegate - should panic with 'the show must go on'")
	}
}

// test_on_channel_close_confirm_only_ibc
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3730-L3756
func TestOnChannelCloseConfirmOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	// Do NOT impersonate core - call from a non-core realm
	// The caller gate runs before the close rejection
	uassert.AbortsContains(t, cur, "only core can", func() {
		(&App{}).OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	})

	// impl should not be called when caller is not IBC host
	if d.closeConfirmCalled {
		t.Fatal("OnChannelCloseConfirm must not delegate for non-IBC caller")
	}
}

// Note: Union checks pause for ALL IBC callbacks including channel handshake
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L137

// Test that paused blocks OnChannelOpenInit
// Union behavior: ensure_not_paused is called for all IbcUnionMsg variants
func TestOnChannelOpenInitPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// Union: paused check happens before any callback logic
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	})

	// impl should NOT be called when paused
	if d.openInitCalled {
		t.Fatal("paused must block OnChannelOpenInit")
	}
}

// Test that paused blocks OnChannelOpenTry
func TestOnChannelOpenTryPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))
	})

	// impl should NOT be called when paused
	if d.openTryCalled {
		t.Fatal("paused must block OnChannelOpenTry")
	}
}

// Test that paused blocks OnChannelOpenAck
func TestOnChannelOpenAckPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer"))
	})

	// impl should NOT be called when paused
	if d.openAckCalled {
		t.Fatal("paused must block OnChannelOpenAck")
	}
}

// Test that paused blocks OnChannelOpenConfirm
func TestOnChannelOpenConfirmPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelOpenConfirm(cross(cur), 2, address("g1relayer"))
	})

	// impl should NOT be called when paused
	if d.openConfirmCalled {
		t.Fatal("paused must block OnChannelOpenConfirm")
	}
}

// Test that close callbacks are also blocked by pause (though they would panic anyway)
func TestOnChannelCloseInitPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// Pause check happens before "the show must go on" panic
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
	})

	// impl should NOT be called when paused
	if d.closeInitCalled {
		t.Fatal("paused must block OnChannelCloseInit")
	}
}

func TestOnChannelCloseConfirmPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// Pause check happens before "the show must go on" panic
	uassert.AbortsContains(t, cur, "zkgm: paused", func() {
		(&App{}).OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
	})

	// impl should NOT be called when paused
	if d.closeConfirmCalled {
		t.Fatal("paused must block OnChannelCloseConfirm")
	}
}

// ============================================================================
// Additional Union-aligned Tests
// ============================================================================

// Test all IBC host caller validation for channel callbacks
// Ensures only core realm can call channel handshake methods
func TestAllChannelCallbacksRequireIbcHost(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	// Test each channel callback without impersonating core
	callbacks := []func(){
		func() { (&App{}).OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer")) },
		func() { (&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer")) },
		func() { (&App{}).OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer")) },
		func() { (&App{}).OnChannelOpenConfirm(cross(cur), 2, address("g1relayer")) },
		func() { (&App{}).OnChannelCloseInit(cross(cur), 2, address("g1relayer")) },
		func() { (&App{}).OnChannelCloseConfirm(cross(cur), 2, address("g1relayer")) },
	}

	for i, cb := range callbacks {
		resetZkgmForTest()
		impl = d
		uassert.AbortsContains(t, cur, "only core can", func() { cb() })

		// Verify no delegation happened
		if d.openInitCalled || d.openTryCalled || d.openAckCalled || d.openConfirmCalled || d.closeInitCalled || d.closeConfirmCalled {
			t.Fatalf("callback %d must not delegate for non-IBC caller", i)
		}
	}
}

// Test that version validation works correctly for all versioned callbacks
func TestVersionValidationUnionAligned(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	// OnChannelOpenInit with invalid version
	uassert.AbortsContains(t, cur, "unsupported channel version", func() {
		(&App{}).OnChannelOpenInit(cross(cur), 1, 2, "wrong-version", address("g1relayer"))
	})

	// OnChannelOpenTry with invalid local version
	uassert.AbortsContains(t, cur, "unsupported channel version", func() {
		(&App{}).OnChannelOpenTry(cross(cur), 1, 2, "wrong-version", Version, address("g1relayer"))
	})

	// OnChannelOpenTry with invalid counterparty version
	uassert.AbortsContains(t, cur, "unsupported channel version", func() {
		(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, "wrong-version", address("g1relayer"))
	})

	// Verify no delegation happened for any invalid version calls
	if d.openInitCalled || d.openTryCalled {
		t.Fatal("version validation must prevent delegation")
	}

	// Valid versions should succeed
	(&App{}).OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))

	if !d.openInitCalled || !d.openTryCalled {
		t.Fatal("valid versions must delegate to impl")
	}
}

// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L713-L746
func TestOnRecvPacketOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "only core can recv", func() {
		(&App{}).OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	})

	// IBC caller delegates to impl
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	res := (&App{}).OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)
	if !d.recvCalled || res.Status != types.PacketStatusSuccess {
		t.Fatal("OnRecvPacket must delegate to impl when called by IBC")
	}
}

// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L168-L182
func TestOnIntentRecvPacketOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "only core can intent recv", func() {
		(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	})

	// IBC caller delegates to impl
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	res := (&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	if !d.recvCalled || res.Status != types.PacketStatusSuccess {
		t.Fatal("OnIntentRecvPacket must delegate to impl when called by IBC")
	}
}

// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L183-L192
func TestOnAcknowledgementPacketOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "only core can ack", func() {
		(&App{}).OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	})

	// IBC caller delegates to impl
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	(&App{}).OnAcknowledgementPacket(cross(cur), packet, []byte{0x01}, address("g1relayer"))
	if !d.ackCalled {
		t.Fatal("OnAcknowledgementPacket must delegate to impl when called by IBC")
	}
}

// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L193-L201
func TestOnTimeoutPacketOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "only core can timeout", func() {
		(&App{}).OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})

	// IBC caller delegates to impl
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	(&App{}).OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	if !d.timeoutCalled {
		t.Fatal("OnTimeoutPacket must delegate to impl when called by IBC")
	}
}
