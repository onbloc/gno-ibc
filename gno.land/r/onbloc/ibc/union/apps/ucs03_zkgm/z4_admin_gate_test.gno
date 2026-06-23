package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestPausable(cur realm, t *testing.T) {
	admin := core.GetAdmin()
	nonAdmin := address("g1notadmin")

	cases := []struct {
		name        string
		caller      address
		values      []bool
		wantAbort   string
		wantPaused  bool
		assertAfter func()
	}{
		{
			name:       "rejects non-admin",
			caller:     nonAdmin,
			values:     []bool{true},
			wantAbort:  "zkgm: admin only",
			wantPaused: false,
			assertAfter: func() {
				if paused {
					t.Error("rejected Pausable must not set paused=true")
				}
			},
		},
		{
			name:       "admin toggles pause state",
			caller:     admin,
			values:     []bool{true, false},
			wantPaused: false,
			assertAfter: func() {
				if paused {
					t.Error("Pausable(false) by admin must set paused=false")
				}
			},
		},
	}

	for _, tc := range cases {
		resetZkgmForTest()

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(tc.caller))
				Pausable(cross(cur), tc.values[0])
			})
			if paused != tc.wantPaused {
				t.Errorf("%s: paused = %v, want %v", tc.name, paused, tc.wantPaused)
			}
			tc.assertAfter()
			continue
		}

		testing.SetRealm(testing.NewUserRealm(tc.caller))
		for _, value := range tc.values {
			Pausable(cross(cur), value)
			if paused != value {
				t.Errorf("%s: Pausable(%v) left paused = %v", tc.name, value, paused)
			}
		}
		if paused != tc.wantPaused {
			t.Errorf("%s: paused = %v, want %v", tc.name, paused, tc.wantPaused)
		}
		tc.assertAfter()
	}
}

func TestSetBucketConfig(cur realm, t *testing.T) {
	admin := core.GetAdmin()
	nonAdmin := address("g1notadmin")

	cases := []struct {
		name       string
		caller     address
		denom      string
		preConfig  bool
		capacity   uint64
		refillRate uint64
		wantAbort  string
		wantBucket bool
	}{
		{
			name:       "rejects non-admin",
			caller:     nonAdmin,
			denom:      "ugnot",
			capacity:   100,
			refillRate: 10,
			wantAbort:  "zkgm: admin only",
		},
		{
			name:       "admin creates bucket",
			caller:     admin,
			denom:      "ugnot-admin",
			capacity:   100,
			refillRate: 10,
			wantBucket: true,
		},
		{
			name:       "admin updates existing bucket",
			caller:     admin,
			denom:      "ugnot-update",
			preConfig:  true,
			capacity:   200,
			refillRate: 20,
			wantBucket: true,
		},
	}

	for _, tc := range cases {
		resetZkgmForTest()
		if tc.preConfig {
			testing.SetRealm(testing.NewUserRealm(admin))
			SetBucketConfig(cross(cur), tc.denom, u256.NewUint(100), u256.NewUint(10))
		}

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(tc.caller))
				SetBucketConfig(cross(cur), tc.denom, u256.NewUint(tc.capacity), u256.NewUint(tc.refillRate))
			})
			if _, ok := store.GetTokenBucket(tc.denom); ok {
				t.Errorf("%s: rejected SetBucketConfig must not create a bucket", tc.name)
			}
			continue
		}

		testing.SetRealm(testing.NewUserRealm(tc.caller))
		SetBucketConfig(cross(cur), tc.denom, u256.NewUint(tc.capacity), u256.NewUint(tc.refillRate))

		bucket, ok := store.GetTokenBucket(tc.denom)
		if ok != tc.wantBucket {
			t.Errorf("%s: bucket exists = %v, want %v", tc.name, ok, tc.wantBucket)
			continue
		}
		if !ok {
			continue
		}
		if !bucket.Capacity.Eq(u256.NewUint(tc.capacity)) {
			t.Errorf("%s: capacity = %s, want %d", tc.name, bucket.Capacity.ToString(), tc.capacity)
		}
		if !bucket.RefillRate.Eq(u256.NewUint(tc.refillRate)) {
			t.Errorf("%s: refill rate = %s, want %d", tc.name, bucket.RefillRate.ToString(), tc.refillRate)
		}
	}
}

func TestSetRateLimitDisabled(cur realm, t *testing.T) {
	admin := core.GetAdmin()
	nonAdmin := address("g1notadmin")

	cases := []struct {
		name         string
		caller       address
		disabled     bool
		wantAbort    string
		wantDisabled bool
	}{
		{
			name:         "rejects non-admin",
			caller:       nonAdmin,
			disabled:     false,
			wantAbort:    "zkgm: admin only",
			wantDisabled: true,
		},
		{
			name:         "admin enables rate limiting",
			caller:       admin,
			disabled:     false,
			wantDisabled: false,
		},
	}

	for _, tc := range cases {
		resetZkgmForTest()

		if tc.wantAbort != "" {
			// Default is disabled (true); a rejected non-admin toggle to false must not stick.
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(tc.caller))
				SetRateLimitDisabled(cross(cur), tc.disabled)
			})
			if store.RateLimitDisabled() != tc.wantDisabled {
				t.Errorf("%s: rate-limit disabled = %v, want %v", tc.name, store.RateLimitDisabled(), tc.wantDisabled)
			}
			continue
		}

		// Default is disabled (true); admin enables rate limiting by setting false.
		testing.SetRealm(testing.NewUserRealm(tc.caller))
		SetRateLimitDisabled(cross(cur), tc.disabled)
		if store.RateLimitDisabled() != tc.wantDisabled {
			t.Errorf("%s: rate-limit disabled = %v, want %v", tc.name, store.RateLimitDisabled(), tc.wantDisabled)
		}

		// Reset the shared singleton flag so later tests see the default.
		resetZkgmForTest()
	}
}
