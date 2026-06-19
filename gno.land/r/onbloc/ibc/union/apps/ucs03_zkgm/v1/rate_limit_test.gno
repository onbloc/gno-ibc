package impl

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

func TestRateLimitNoBucketIsUnlimited(cur realm, t *testing.T) {
	v := newTestImpl()
	uassert.NoError(t, v.rateLimit(0, cur, "ratelimit-none", u256.NewUint(1_000_000)))
}

func TestRateLimitNilAmountIsNoop(cur realm, t *testing.T) {
	v := newTestImpl()
	uassert.NoError(t, v.rateLimit(0, cur, "ratelimit-nil", nil))
}

func TestRateLimitChargesAndExhausts(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ratelimit-charge"
	// refillRate 1/s with same-block now means no meaningful refill, so the
	// bucket behaves as a fixed capacity over the test's window.
	bucket, err := tb.New(u256.NewUint(100), u256.NewUint(1), blockNow())
	uassert.NoError(t, err)
	testStore.SetTokenBucket(0, cur, denom, bucket)

	uassert.NoError(t, v.rateLimit(0, cur, denom, u256.NewUint(60)))
	uassert.Error(t, v.rateLimit(0, cur, denom, u256.NewUint(60)))
}

func TestRateLimitExactCapacitySucceedsThenEmpty(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ratelimit-exact"
	bucket, err := tb.New(u256.NewUint(100), u256.NewUint(1), blockNow())
	uassert.NoError(t, err)
	testStore.SetTokenBucket(0, cur, denom, bucket)

	// draining exactly the capacity is allowed; a full re-charge then exceeds.
	uassert.NoError(t, v.rateLimit(0, cur, denom, u256.NewUint(100)))
	uassert.Error(t, v.rateLimit(0, cur, denom, u256.NewUint(100)))
	// a zero charge against an empty bucket is still fine.
	uassert.NoError(t, v.rateLimit(0, cur, denom, u256.Zero()))
}

func TestRateLimitDisabledBypassesBucket(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ratelimit-disabled"
	bucket, err := tb.New(u256.NewUint(1), u256.NewUint(1), blockNow())
	uassert.NoError(t, err)
	testStore.SetTokenBucket(0, cur, denom, bucket)

	testStore.SetRateLimitDisabled(0, cur, true)
	uassert.NoError(t, v.rateLimit(0, cur, denom, u256.NewUint(1_000_000)))
	testStore.SetRateLimitDisabled(0, cur, false)
}
