// Ported from Union CosmWasm tests
// Reference: https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/tests.rs
package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Version enforcement lives in the installed impl; the proxy only gates caller
// and pause state before delegating.
func TestOnChannelOpenInitDelegatesVersionToImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	(&App{}).OnChannelOpenInit(cross(cur), 1, 2, "im-invalid", address("g1relayer"))

	if !d.openInitCalled {
		t.Fatal("OnChannelOpenInit must delegate version validation to impl")
	}
}

func TestOnChannelOpenTryDelegatesVersionToImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	(&App{}).OnChannelOpenTry(cross(cur), 1, 2, "im-invalid", Version, address("g1relayer"))

	if !d.openTryCalled {
		t.Fatal("OnChannelOpenTry must delegate version validation to impl")
	}
}

func TestOnChannelOpenTryDelegatesCounterpartyVersionToImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d

	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))

	(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, "im-invalid", address("g1relayer"))

	if !d.openTryCalled || d.lastCounterpartyVer != "im-invalid" {
		t.Fatal("OnChannelOpenTry must delegate counterparty version validation to impl")
	}
}

// Test that paused blocks OnChannelOpenTry
func TestOnChannelOpenTryPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d
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
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d
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
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d
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
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d
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
	resetZkgmForTest(cur)
	d := &dummyImpl{}
	currentImpl = d
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
	resetZkgmForTest(cur)
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
		resetZkgmForTest(cur)
		currentImpl = d
		uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() { cb() })

		// Verify no delegation happened
		if d.openInitCalled || d.openTryCalled || d.openAckCalled || d.openConfirmCalled || d.closeInitCalled || d.closeConfirmCalled {
			t.Fatalf("callback %d must not delegate for non-IBC caller", i)
		}
	}
}

func TestAppDelegatesVersionValidationToImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
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
	resetZkgmForTest(cur)
	d = &dummyImpl{}
	currentImpl = d
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	(&App{}).OnChannelOpenInit(cross(cur), 1, 2, Version, address("g1relayer"))
	(&App{}).OnChannelOpenTry(cross(cur), 1, 2, Version, Version, address("g1relayer"))

	if !d.openInitCalled || !d.openTryCalled {
		t.Fatal("valid versions must delegate to impl")
	}
}
