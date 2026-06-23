package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/onbloc/ibc/union/access"
)

func TestPausableRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "access manager unauthorized call", func(cur realm) {
		Pausable(cross(cur), true)
	})
	if paused {
		t.Error("rejected Pausable must not set paused=true")
	}
}

func TestPausableSetByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	Pausable(cross(cur), true)
	if !paused {
		t.Error("Pausable(true) by admin must set paused=true")
	}

	Pausable(cross(cur), false)
	if paused {
		t.Error("Pausable(false) by admin must set paused=false")
	}
}

func TestSetBucketConfigRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "access manager unauthorized call", func(cur realm) {
		SetBucketConfig(cross(cur), "ugnot", u256.NewUint(100), u256.NewUint(10))
	})
	if _, ok := store.GetTokenBucket("ugnot"); ok {
		t.Error("rejected SetBucketConfig must not create a bucket")
	}
}

func TestSetBucketConfigSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	SetBucketConfig(cross(cur), "ugnot-admin", u256.NewUint(100), u256.NewUint(10))

	if _, ok := store.GetTokenBucket("ugnot-admin"); !ok {
		t.Error("SetBucketConfig by admin must create a bucket")
	}
}

func TestSetBucketConfigRejectsInvalidBoundsByAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name       string
		denom      string
		seedBucket bool
		capacity   *u256.Uint
		refillRate *u256.Uint
		wantAbort  string
		wantExists bool
		wantCap    uint64
		wantRefill uint64
	}{
		{
			name:       "new bucket zero capacity",
			denom:      "ugnot-zero-capacity",
			capacity:   u256.Zero(),
			refillRate: u256.NewUint(10),
			wantAbort:  "capacity must not be zero",
		},
		{
			name:       "new bucket zero refill",
			denom:      "ugnot-zero-refill",
			capacity:   u256.NewUint(100),
			refillRate: u256.Zero(),
			wantAbort:  "refill rate must not be zero",
		},
		{
			name:       "existing bucket zero capacity preserves old config",
			denom:      "ugnot-existing-zero-capacity",
			seedBucket: true,
			capacity:   u256.Zero(),
			refillRate: u256.NewUint(10),
			wantAbort:  "capacity must not be zero",
			wantExists: true,
			wantCap:    100,
			wantRefill: 10,
		},
		{
			name:       "existing bucket zero refill preserves old config",
			denom:      "ugnot-existing-zero-refill",
			seedBucket: true,
			capacity:   u256.NewUint(100),
			refillRate: u256.Zero(),
			wantAbort:  "refill rate must not be zero",
			wantExists: true,
			wantCap:    100,
			wantRefill: 10,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetZkgmForTest(cur)
			if tc.seedBucket {
				uassert.NotAborts(t, cur, func(cur realm) {
					testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
					SetBucketConfig(cross(cur), tc.denom, u256.NewUint(100), u256.NewUint(10))
				})
			}

			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
				SetBucketConfig(cross(cur), tc.denom, tc.capacity, tc.refillRate)
			})

			bucket, ok := store.GetTokenBucket(tc.denom)
			uassert.Equal(t, tc.wantExists, ok)
			if tc.wantExists {
				uassert.True(t, bucket.Capacity.Eq(u256.NewUint(tc.wantCap)))
				uassert.True(t, bucket.RefillRate.Eq(u256.NewUint(tc.wantRefill)))
			}
		})
	}
}

func TestSetRateLimitDisabledRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	// Default is disabled (true); a rejected non-admin toggle to false must not stick.
	uassert.AbortsContains(t, cur, "access manager unauthorized call", func(cur realm) {
		SetRateLimitDisabled(cross(cur), false)
	})
	if !store.RateLimitDisabled() {
		t.Error("rejected SetRateLimitDisabled must not toggle the kill-switch")
	}
}

func TestSetRateLimitDisabledSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	// Default is disabled (true); admin enables rate limiting by setting false.
	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	SetRateLimitDisabled(cross(cur), false)
	if store.RateLimitDisabled() {
		t.Error("SetRateLimitDisabled by admin must clear the kill-switch")
	}

	// Reset the shared singleton flag so later tests see the default.
	resetZkgmForTest(cur)
}
