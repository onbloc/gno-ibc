package zkgm

import (
	"chain/runtime"

	tb "gno.land/p/onbloc/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func Pause(cur realm) {
	mustBeAdmin(cur)
	paused = true
}

func Unpause(cur realm) {
	mustBeAdmin(cur)
	paused = false
}

// SetBucketConfig creates or updates the per-denom token bucket used for send-side
// rate limiting. The bucket is anchored to block time (time.Now().Unix()), so
// RefillRate is in tokens per second. Admin-only.
func SetBucketConfig(cur realm, denom string, capacity *u256.Uint, refillRate *u256.Uint) {
	mustBeAdmin(cur)

	bucket := GetTokenBucket(denom)
	if bucket == nil {
		var err error
		bucket, err = tb.New(capacity, refillRate, blockNow())
		if err != nil {
			panic(err)
		}

		// Direct ledger write: SetTokenBucket gates on requireImplRealm, but
		// admin is not in the allowed-impls list. v0 admin uses the same bypass.
		tokenBucket.Set(denom, bucket)
		return
	}

	if err := bucket.Update(capacity, refillRate, false); err != nil {
		panic(err)
	}
}

// SetRateLimitDisabled toggles the global rate-limit kill switch. Admin-only.
func SetRateLimitDisabled(cur realm, disabled bool) {
	mustBeAdmin(cur)
	rateLimitDisabled = disabled
}

func mustBeAdmin(cur realm) {
	admin := core.GetAdmin()
	runtime.AssertOriginCall()
	if cur.Previous().Address() != admin {
		panic("zkgm: admin only")
	}
}
