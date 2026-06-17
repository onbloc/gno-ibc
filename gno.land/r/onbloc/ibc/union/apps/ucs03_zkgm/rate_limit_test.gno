package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

func TestRateLimitLifecycle(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = ProxyPkgPath()

	denom := "v1-rate-limit-lifecycle"
	rateLimitDisabled = false
	bucket, bucketErr := tb.New(u256.NewUint(10), u256.NewUint(1), blockNow())
	if bucketErr != nil {
		t.Fatal(bucketErr)
	}
	tokenBucket.Set(denom, bucket)

	err := RateLimit(cross(cur), denom, u256.NewUint(7))
	uassert.NoError(t, err)

	err = RateLimit(cross(cur), denom, u256.NewUint(4))
	uassert.ErrorContains(t, err, "token bucket rate limit exceeded")

	rateLimitDisabled = true

	err = RateLimit(cross(cur), denom, u256.NewUint(100))
	uassert.NoError(t, err)

	rateLimitDisabled = false
}

func TestTokenBucketRefillAllowsLaterCharge(t *testing.T) {
	bucket, bucketErr := tb.New(u256.NewUint(10), u256.NewUint(2), u256.NewUint(100))
	if bucketErr != nil {
		t.Fatal(bucketErr)
	}

	err := bucket.RateLimit(u256.NewUint(10), u256.NewUint(100))
	uassert.NoError(t, err)

	err = bucket.RateLimit(u256.NewUint(1), u256.NewUint(100))
	uassert.ErrorContains(t, err, "token bucket rate limit exceeded")

	err = bucket.RateLimit(u256.NewUint(4), u256.NewUint(102))
	uassert.NoError(t, err)
}
