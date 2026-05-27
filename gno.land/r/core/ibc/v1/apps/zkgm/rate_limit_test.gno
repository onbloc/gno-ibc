package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestRateLimitLifecycle(cur realm, t *testing.T) {
	denom := "v1-rate-limit-lifecycle"
	SetRateLimitDisabled(cross(cur), false)
	SetBucketConfig(cross(cur), denom, u256.NewUint(10), u256.NewUint(1))

	err := RateLimit(cross(cur), denom, u256.NewUint(7))
	uassert.NoError(t, err)

	err = RateLimit(cross(cur), denom, u256.NewUint(4))
	uassert.ErrorContains(t, err, "token bucket rate limit exceeded")

	SetRateLimitDisabled(cross(cur), true)

	err = RateLimit(cross(cur), denom, u256.NewUint(100))
	uassert.NoError(t, err)

	SetRateLimitDisabled(cross(cur), false)
}
