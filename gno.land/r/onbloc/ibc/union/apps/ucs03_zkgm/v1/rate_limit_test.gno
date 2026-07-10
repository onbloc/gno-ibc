package ucs03_zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

func TestRateLimit(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(cur realm, t *testing.T, v *ucs03ZkgmV1)
	}{
		{
			name: "disabled is noop",
			run: func(cur realm, t *testing.T, v *ucs03ZkgmV1) {
				uassert.NoError(t, v.rateLimit(0, cur, "ratelimit-default-off", u256.NewUint(1_000_000)))
			},
		},
		{
			name: "absent bucket rejected",
			run: func(cur realm, t *testing.T, v *ucs03ZkgmV1) {
				testStore.SetRateLimitDisabled(0, cur, false)

				err := v.rateLimit(0, cur, "ratelimit-no-bucket", u256.NewUint(1))
				uassert.ErrorContains(t, err, "token bucket is absent")
			},
		},
		{
			name: "nil amount is noop",
			run: func(cur realm, t *testing.T, v *ucs03ZkgmV1) {
				testStore.SetRateLimitDisabled(0, cur, false)

				uassert.NoError(t, v.rateLimit(0, cur, "ratelimit-nil", nil))
			},
		},
		{
			name: "charges and exhausts",
			run: func(cur realm, t *testing.T, v *ucs03ZkgmV1) {
				testStore.SetRateLimitDisabled(0, cur, false)
				denom := "ratelimit-charge"
				bucket, err := tb.New(u256.NewUint(100), u256.NewUint(1), blockNow())
				uassert.NoError(t, err)
				testStore.SetTokenBucket(0, cur, denom, bucket)

				uassert.NoError(t, v.rateLimit(0, cur, denom, u256.NewUint(60)))
				uassert.Error(t, v.rateLimit(0, cur, denom, u256.NewUint(60)))
			},
		},
		{
			name: "exact capacity succeeds then empty",
			run: func(cur realm, t *testing.T, v *ucs03ZkgmV1) {
				testStore.SetRateLimitDisabled(0, cur, false)
				denom := "ratelimit-exact"
				bucket, err := tb.New(u256.NewUint(100), u256.NewUint(1), blockNow())
				uassert.NoError(t, err)
				testStore.SetTokenBucket(0, cur, denom, bucket)

				uassert.NoError(t, v.rateLimit(0, cur, denom, u256.NewUint(100)))
				uassert.Error(t, v.rateLimit(0, cur, denom, u256.NewUint(100)))
				uassert.NoError(t, v.rateLimit(0, cur, denom, u256.Zero()))
			},
		},
		{
			name: "disabled bypasses bucket",
			run: func(cur realm, t *testing.T, v *ucs03ZkgmV1) {
				denom := "ratelimit-disabled"
				bucket, err := tb.New(u256.NewUint(1), u256.NewUint(1), blockNow())
				uassert.NoError(t, err)
				testStore.SetTokenBucket(0, cur, denom, bucket)
				testStore.SetRateLimitDisabled(0, cur, true)

				uassert.NoError(t, v.rateLimit(0, cur, denom, u256.NewUint(1_000_000)))
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			tc.run(cur, t, newTestImpl())
		})
	}
}

// enableRateLimit enables rate limiting for the given realm and returns a
// restore function that disables it again.
//
// Rate limiting is disabled by default in the shared testStore.
func enableRateLimit(cur realm) func() {
	testStore.SetRateLimitDisabled(0, cur, false)
	return func() { testStore.SetRateLimitDisabled(0, cur, true) }
}
