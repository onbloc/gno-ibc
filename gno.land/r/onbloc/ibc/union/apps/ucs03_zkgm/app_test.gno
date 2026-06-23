// Ported from Union CosmWasm tests
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs
package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"

	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/core"
)

func newAppTestImpl(pausedState bool) *dummyImpl {
	resetZkgmForTest()
	d := &dummyImpl{}
	currentImpl = d
	paused = pausedState
	return d
}

func TestOnChannelOpenInit(cur realm, t *testing.T) {
	cases := []struct {
		name       string
		coreCaller bool
		paused     bool
		version    string
		wantAbort  string
		check      func(t *testing.T, d *dummyImpl)
	}{
		// test_on_channel_open_init_ok
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3380-L3402
		{
			name:       "ok",
			coreCaller: true,
			version:    Version,
			check: func(t *testing.T, d *dummyImpl) {
				if !d.openInitCalled || d.lastChannelId != 2 {
					t.Fatal("OnChannelOpenInit must delegate to impl")
				}
			},
		},
		// Version enforcement lives in the installed impl; the proxy only gates caller
		// and pause state before delegating.
		{
			name:       "delegates version validation to impl",
			coreCaller: true,
			version:    "im-invalid",
			check: func(t *testing.T, d *dummyImpl) {
				if !d.openInitCalled {
					t.Fatal("OnChannelOpenInit must delegate version validation to impl")
				}
			},
		},
		// test_on_channel_open_init_only_ibc
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3438-L3466
		{
			name:       "only ibc",
			coreCaller: false,
			version:    Version,
			wantAbort:  "zkgm: ibc host only",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should not be called when caller is not IBC host
				if d.openInitCalled {
					t.Fatal("OnChannelOpenInit must not delegate for non-IBC caller")
				}
			},
		},
		// Note: Union checks pause for ALL IBC callbacks including channel handshake
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L137
		//
		// Test that paused blocks OnChannelOpenInit
		// Union behavior: ensure_not_paused is called for all IbcUnionMsg variants
		{
			name:       "paused blocks",
			coreCaller: true,
			paused:     true,
			version:    Version,
			wantAbort:  "zkgm: paused",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called when paused
				if d.openInitCalled {
					t.Fatal("paused must block OnChannelOpenInit")
				}
			},
		},
	}

	for _, tc := range cases {
		d := newAppTestImpl(tc.paused)
		if tc.coreCaller {
			// Channel callbacks are gated to the core caller, so impersonate core.
			testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		} else {
			testing.SetRealm(testing.NewCodeRealm("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/noncore"))
		}
		call := func() {
			(&App{}).OnChannelOpenInit(cross(cur), 1, 2, tc.version, address("g1relayer"))
		}
		if tc.wantAbort != "" {
			if tc.wantAbort == "zkgm: ibc host only" {
				// Do NOT impersonate core - call from a non-core realm
			}
			if tc.wantAbort == "zkgm: paused" {
				// Union: paused check happens before any callback logic
			}
			uassert.AbortsContains(t, cur, tc.wantAbort, call)
		} else {
			call()
		}
		tc.check(t, d)
	}
}

func TestOnChannelOpenTry(cur realm, t *testing.T) {
	cases := []struct {
		name                string
		coreCaller          bool
		paused              bool
		version             string
		counterpartyVersion string
		wantAbort           string
		check               func(t *testing.T, d *dummyImpl)
	}{
		// test_on_channel_open_try_ok
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3469-L3492
		{
			name:                "ok",
			coreCaller:          true,
			version:             Version,
			counterpartyVersion: Version,
			check: func(t *testing.T, d *dummyImpl) {
				if !d.openTryCalled || d.lastCounterpartyVer != Version {
					t.Fatal("OnChannelOpenTry must delegate with counterparty version")
				}
			},
		},
		{
			name:                "delegates version validation to impl",
			coreCaller:          true,
			version:             "im-invalid",
			counterpartyVersion: Version,
			check: func(t *testing.T, d *dummyImpl) {
				if !d.openTryCalled {
					t.Fatal("OnChannelOpenTry must delegate version validation to impl")
				}
			},
		},
		{
			name:                "delegates counterparty version validation to impl",
			coreCaller:          true,
			version:             Version,
			counterpartyVersion: "im-invalid",
			check: func(t *testing.T, d *dummyImpl) {
				if !d.openTryCalled || d.lastCounterpartyVer != "im-invalid" {
					t.Fatal("OnChannelOpenTry must delegate counterparty version validation to impl")
				}
			},
		},
		// test_on_channel_open_try_only_ibc
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3563-L3592
		{
			name:                "only ibc",
			coreCaller:          false,
			version:             Version,
			counterpartyVersion: Version,
			wantAbort:           "zkgm: ibc host only",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should not be called when caller is not IBC host
				if d.openTryCalled {
					t.Fatal("OnChannelOpenTry must not delegate for non-IBC caller")
				}
			},
		},
		// Note: Union checks pause for ALL IBC callbacks including channel handshake
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L137
		//
		// Test that paused blocks OnChannelOpenTry
		{
			name:                "paused blocks",
			coreCaller:          true,
			paused:              true,
			version:             Version,
			counterpartyVersion: Version,
			wantAbort:           "zkgm: paused",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called when paused
				if d.openTryCalled {
					t.Fatal("paused must block OnChannelOpenTry")
				}
			},
		},
	}

	for _, tc := range cases {
		d := newAppTestImpl(tc.paused)
		if tc.coreCaller {
			testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		} else {
			testing.SetRealm(testing.NewCodeRealm("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/noncore"))
		}
		call := func() {
			(&App{}).OnChannelOpenTry(cross(cur), 1, 2, tc.version, tc.counterpartyVersion, address("g1relayer"))
		}
		if tc.wantAbort != "" {
			if tc.wantAbort == "zkgm: ibc host only" {
				// Do NOT impersonate core - call from a non-core realm
			}
			uassert.AbortsContains(t, cur, tc.wantAbort, call)
		} else {
			call()
		}
		tc.check(t, d)
	}
}

func TestOnChannelOpenAck(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		paused    bool
		wantAbort string
		check     func(t *testing.T, d *dummyImpl)
	}{
		// test_on_channel_open_ack_and_confirm_noop
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3595-L3640
		{
			name: "noop delegates",
			check: func(t *testing.T, d *dummyImpl) {
				if !d.openAckCalled {
					t.Fatal("OnChannelOpenAck must delegate to impl")
				}
			},
		},
		// Test that paused blocks OnChannelOpenAck
		{
			name:      "paused blocks",
			paused:    true,
			wantAbort: "zkgm: paused",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called when paused
				if d.openAckCalled {
					t.Fatal("paused must block OnChannelOpenAck")
				}
			},
		},
	}

	for _, tc := range cases {
		d := newAppTestImpl(tc.paused)
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		call := func() {
			// OnChannelOpenAck should delegate to impl (no-op in current impl)
			(&App{}).OnChannelOpenAck(cross(cur), 2, 3, Version, address("g1relayer"))
		}
		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, call)
		} else {
			call()
		}
		tc.check(t, d)
	}
}

func TestOnChannelOpenConfirm(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		paused    bool
		wantAbort string
		check     func(t *testing.T, d *dummyImpl)
	}{
		// test_on_channel_open_ack_and_confirm_noop
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3595-L3640
		{
			name: "noop delegates",
			check: func(t *testing.T, d *dummyImpl) {
				if !d.openConfirmCalled {
					t.Fatal("OnChannelOpenConfirm must delegate to impl")
				}
			},
		},
		// Test that paused blocks OnChannelOpenConfirm
		{
			name:      "paused blocks",
			paused:    true,
			wantAbort: "zkgm: paused",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called when paused
				if d.openConfirmCalled {
					t.Fatal("paused must block OnChannelOpenConfirm")
				}
			},
		},
	}

	for _, tc := range cases {
		d := newAppTestImpl(tc.paused)
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		call := func() {
			// OnChannelOpenConfirm should delegate to impl (no-op in current impl)
			(&App{}).OnChannelOpenConfirm(cross(cur), 2, address("g1relayer"))
		}
		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, call)
		} else {
			call()
		}
		tc.check(t, d)
	}
}

func TestOnChannelCloseInit(cur realm, t *testing.T) {
	cases := []struct {
		name       string
		coreCaller bool
		paused     bool
		wantAbort  string
		check      func(t *testing.T, d *dummyImpl)
	}{
		// test_on_channel_close_init_impossible
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3643-L3669
		// Union implementation: "the show must go on" error for all close callbacks
		{
			name:       "impossible",
			coreCaller: true,
			wantAbort:  "the show must go on",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called - we reject before delegation
				if d.closeInitCalled {
					t.Fatal("OnChannelCloseInit must not delegate - should panic with 'the show must go on'")
				}
			},
		},
		// test_on_channel_close_init_only_ibc
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3672-L3698
		{
			name:       "only ibc",
			coreCaller: false,
			wantAbort:  "zkgm: ibc host only",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should not be called when caller is not IBC host
				if d.closeInitCalled {
					t.Fatal("OnChannelCloseInit must not delegate for non-IBC caller")
				}
			},
		},
		// Test that close callbacks are also blocked by pause (though they would panic anyway)
		{
			name:       "paused blocks",
			coreCaller: true,
			paused:     true,
			wantAbort:  "zkgm: paused",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called when paused
				if d.closeInitCalled {
					t.Fatal("paused must block OnChannelCloseInit")
				}
			},
		},
	}

	for _, tc := range cases {
		d := newAppTestImpl(tc.paused)
		if tc.coreCaller {
			testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		} else {
			testing.SetRealm(testing.NewCodeRealm("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/noncore"))
		}
		call := func() {
			(&App{}).OnChannelCloseInit(cross(cur), 2, address("g1relayer"))
		}
		if tc.wantAbort == "zkgm: ibc host only" {
			// Do NOT impersonate core - call from a non-core realm
			// The caller gate runs before the close rejection
		}
		if tc.wantAbort == "the show must go on" {
			// Union rejects close init with "the show must go on" error
		}
		if tc.wantAbort == "zkgm: paused" {
			// Pause check happens before "the show must go on" panic
		}
		uassert.AbortsContains(t, cur, tc.wantAbort, call)
		tc.check(t, d)
	}
}

func TestOnChannelCloseConfirm(cur realm, t *testing.T) {
	cases := []struct {
		name       string
		coreCaller bool
		paused     bool
		wantAbort  string
		check      func(t *testing.T, d *dummyImpl)
	}{
		// test_on_channel_close_confirm_impossible
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3701-L3727
		// Union implementation: "the show must go on" error for all close callbacks
		{
			name:       "impossible",
			coreCaller: true,
			wantAbort:  "the show must go on",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called - we reject before delegation
				if d.closeConfirmCalled {
					t.Fatal("OnChannelCloseConfirm must not delegate - should panic with 'the show must go on'")
				}
			},
		},
		// test_on_channel_close_confirm_only_ibc
		// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs#L3730-L3756
		{
			name:       "only ibc",
			coreCaller: false,
			wantAbort:  "zkgm: ibc host only",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should not be called when caller is not IBC host
				if d.closeConfirmCalled {
					t.Fatal("OnChannelCloseConfirm must not delegate for non-IBC caller")
				}
			},
		},
		{
			name:       "paused blocks",
			coreCaller: true,
			paused:     true,
			wantAbort:  "zkgm: paused",
			check: func(t *testing.T, d *dummyImpl) {
				// impl should NOT be called when paused
				if d.closeConfirmCalled {
					t.Fatal("paused must block OnChannelCloseConfirm")
				}
			},
		},
	}

	for _, tc := range cases {
		d := newAppTestImpl(tc.paused)
		if tc.coreCaller {
			testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		} else {
			testing.SetRealm(testing.NewCodeRealm("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/noncore"))
		}
		call := func() {
			(&App{}).OnChannelCloseConfirm(cross(cur), 2, address("g1relayer"))
		}
		if tc.wantAbort == "zkgm: ibc host only" {
			// Do NOT impersonate core - call from a non-core realm
			// The caller gate runs before the close rejection
		}
		if tc.wantAbort == "the show must go on" {
			// Union rejects close confirm with "the show must go on" error
		}
		if tc.wantAbort == "zkgm: paused" {
			// Pause check happens before "the show must go on" panic
		}
		uassert.AbortsContains(t, cur, tc.wantAbort, call)
		tc.check(t, d)
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
	currentImpl = d

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
		currentImpl = d
		uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() { cb() })

		// Verify no delegation happened
		if d.openInitCalled || d.openTryCalled || d.openAckCalled || d.openConfirmCalled || d.closeInitCalled || d.closeConfirmCalled {
			t.Fatalf("callback %d must not delegate for non-IBC caller", i)
		}
	}
}

func TestAppDelegatesVersionValidationToImpl(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	currentImpl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	(&App{}).OnChannelOpenInit(cross(cur), 1, 2, "wrong-version", address("g1relayer"))
	(&App{}).OnChannelOpenTry(cross(cur), 1, 2, "wrong-version", Version, address("g1relayer"))
	(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, "wrong-version", address("g1relayer"))

	if !d.openInitCalled || !d.openTryCalled || d.lastCounterpartyVer != "wrong-version" {
		t.Fatal("app must delegate version validation to impl")
	}

	// Valid versions should succeed
	resetZkgmForTest()
	d = &dummyImpl{}
	currentImpl = d
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
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
	currentImpl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
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
	currentImpl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
		(&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	})

	// IBC caller delegates to impl
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	res := (&App{}).OnIntentRecvPacket(cross(cur), packet, address("g1maker"), nil)
	if !d.intentRecvCalled || res.Status != types.PacketStatusSuccess {
		t.Fatal("OnIntentRecvPacket must delegate to impl when called by IBC")
	}
}

// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L183-L192
func TestOnAcknowledgementPacketOnlyIbc(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	currentImpl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
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
	currentImpl = d
	packet := core.NewPacket(1, 2, []byte("data"), 0)

	// Non-IBC caller is rejected
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
		(&App{}).OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	})

	// IBC caller delegates to impl
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	(&App{}).OnTimeoutPacket(cross(cur), packet, address("g1relayer"))
	if !d.timeoutCalled {
		t.Fatal("OnTimeoutPacket must delegate to impl when called by IBC")
	}
}
