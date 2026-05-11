package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestRateLimitLifecycle(cur realm, t *testing.T) {
	denom := "v1-rate-limit-lifecycle"
	SetRateLimitDisabled(cross, false)
	SetBucketConfig(cross, denom, u256.NewUint(10), u256.NewUint(1))

	err := RateLimit(cross, denom, u256.NewUint(7))
	uassert.NoError(t, err)

	err = RateLimit(cross, denom, u256.NewUint(4))
	uassert.ErrorContains(t, err, "token bucket rate limit exceeded")

	SetRateLimitDisabled(cross, true)

	err = RateLimit(cross, denom, u256.NewUint(100))
	uassert.NoError(t, err)

	SetRateLimitDisabled(cross, false)
}
