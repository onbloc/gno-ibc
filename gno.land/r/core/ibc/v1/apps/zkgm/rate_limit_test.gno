package zkgm

import (
	"testing"

	tb "gno.land/p/gnoswap/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
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
