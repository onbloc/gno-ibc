package main

import (
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	zkgm.SetBucketConfig(cross, "ugnot", u256.NewUint(10), u256.NewUint(1), u256.Zero())

	err := zkgm.RateLimit(cross, "ugnot", u256.NewUint(7), u256.Zero())
	println("first_limit_ok", err == nil)

	err = zkgm.RateLimit(cross, "ugnot", u256.NewUint(4), u256.Zero())
	println("second_limit_error", err)

	zkgm.SetRateLimitDisabled(cross, true)
	err = zkgm.RateLimit(cross, "ugnot", u256.NewUint(100), u256.Zero())
	println("disabled_limit_ok", err == nil)
}

// Output:
// first_limit_ok true
// second_limit_error token bucket rate limit exceeded
// disabled_limit_ok true
