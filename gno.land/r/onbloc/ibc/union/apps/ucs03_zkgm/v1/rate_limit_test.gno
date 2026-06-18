package impl

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func TestRateLimitNoBucketIsUnlimited(cur realm, t *testing.T) {
	v := newTestImpl()
	uassert.NoError(t, v.rateLimit(cur, "ratelimit-none", u256.NewUint(1_000_000)))
}

func TestRateLimitNilAmountIsNoop(cur realm, t *testing.T) {
	v := newTestImpl()
	uassert.NoError(t, v.rateLimit(cur, "ratelimit-nil", nil))
}

func TestRateLimitChargesAndExhausts(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ratelimit-charge"
	// refillRate 0 → fixed capacity, no time-based refill.
	bucket, err := tb.New(u256.NewUint(100), u256.Zero(), blockNow())
	uassert.NoError(t, err)
	zkgm.Store().SetTokenBucket(0, cur, denom, bucket)

	uassert.NoError(t, v.rateLimit(cur, denom, u256.NewUint(60)))
	uassert.Error(t, v.rateLimit(cur, denom, u256.NewUint(60)))
}

func TestRateLimitDisabledBypassesBucket(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ratelimit-disabled"
	bucket, err := tb.New(u256.NewUint(1), u256.Zero(), blockNow())
	uassert.NoError(t, err)
	zkgm.Store().SetTokenBucket(0, cur, denom, bucket)

	zkgm.Store().SetRateLimitDisabled(0, cur, true)
	uassert.NoError(t, v.rateLimit(cur, denom, u256.NewUint(1_000_000)))
	zkgm.Store().SetRateLimitDisabled(0, cur, false)
}
