package zkgm

import (
	"chain/runtime"

	tb "gno.land/p/gnoswap/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
)

func SetAdmin(cur realm, admin string) {
	if adminAddressStr != "" && runtime.OriginCaller().String() != adminAddressStr {
		panic("zkgm: admin only")
	}
	adminAddressStr = admin
}

func Pause(cur realm) {
	mustBeAdmin()
	paused = true
}

func Unpause(cur realm) {
	mustBeAdmin()
	paused = false
}

// SetBucketConfig creates or updates the per-denom token bucket used for send-side
// rate limiting. The bucket is anchored to block time (time.Now().Unix()), so
// RefillRate is in tokens per second. Admin-only.
func SetBucketConfig(cur realm, denom string, capacity *u256.Uint, refillRate *u256.Uint) {
	mustBeAdmin()

	bucket := GetTokenBucket(denom)
	if bucket == nil {
		var err error
		bucket, err = tb.New(capacity, refillRate, blockNow())
		if err != nil {
			panic(err)
		}

		// Direct ledger write: SetTokenBucket gates on mustBeAuthorizedImpl, but
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
	mustBeAdmin()
	rateLimitDisabled = disabled
}

func mustBeAdmin() {
	if adminAddressStr == "" {
		return
	}
	if runtime.OriginCaller().String() != adminAddressStr {
		panic("zkgm: admin only")
	}
}
