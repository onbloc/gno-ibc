package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestPausableRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "caller not authorized to pausable", func(cur realm) {
		Pausable(cross(cur), true)
	})
	if paused {
		t.Error("rejected Pausable must not set paused=true")
	}
}

func TestPausableSetByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	Pausable(cur, true)
	if !paused {
		t.Error("Pausable(true) by admin must set paused=true")
	}

	Pausable(cur, false)
	if paused {
		t.Error("Pausable(false) by admin must set paused=false")
	}
}

func TestSetBucketConfigRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "caller not authorized to set_bucket_config", func(cur realm) {
		SetBucketConfig(cross(cur), "ugnot", u256.NewUint(100), u256.NewUint(10))
	})
	if _, ok := store.GetTokenBucket("ugnot"); ok {
		t.Error("rejected SetBucketConfig must not create a bucket")
	}
}

func TestSetBucketConfigSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	SetBucketConfig(cur, "ugnot-admin", u256.NewUint(100), u256.NewUint(10))

	if _, ok := store.GetTokenBucket("ugnot-admin"); !ok {
		t.Error("SetBucketConfig by admin must create a bucket")
	}
}

func TestSetRateLimitDisabledRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	// Default is disabled (true); a rejected non-admin toggle to false must not stick.
	uassert.AbortsContains(t, cur, "caller not authorized to set_rate_limit_disabled", func(cur realm) {
		SetRateLimitDisabled(cross(cur), false)
	})
	if !store.RateLimitDisabled() {
		t.Error("rejected SetRateLimitDisabled must not toggle the kill-switch")
	}
}

func TestSetRateLimitDisabledSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	// Default is disabled (true); admin enables rate limiting by setting false.
	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	SetRateLimitDisabled(cur, false)
	if store.RateLimitDisabled() {
		t.Error("SetRateLimitDisabled by admin must clear the kill-switch")
	}

	// Reset the shared singleton flag so later tests see the default.
	resetZkgmForTest(cur)
}
