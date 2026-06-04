package zkgm

import (
	"chain/runtime"

	tb "gno.land/p/gnoswap/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
)

func Pause(cur realm) {
	mustBeAdmin(cur)
	runtime.AssertOriginCall()
	paused = true
}

func Unpause(cur realm) {
	mustBeAdmin(cur)
	runtime.AssertOriginCall()
	paused = false
}

// SetBucketConfig creates or updates the per-denom token bucket used for send-side
// rate limiting. The bucket is anchored to block time (time.Now().Unix()), so
// RefillRate is in tokens per second. Admin-only.
func SetBucketConfig(cur realm, denom string, capacity *u256.Uint, refillRate *u256.Uint) {
	mustBeAdmin(cur)
	runtime.AssertOriginCall()

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
	mustBeAdmin(cur)
	runtime.AssertOriginCall()
	rateLimitDisabled = disabled
}

// ForceSetImpl overwrites the registered impl, its package path, and the
// allowedImpls list in a single atomic step. Bypasses UpdateImpl's
// allowedImpls gate, so it remains callable even when the list is sealed to a
// broken impl. Admin-only emergency path: use only when the registered impl is
// irrecoverable and normal upgrade governance is blocked.
func ForceSetImpl(cur realm, newImpl ZkgmImpl, path string, newAllowedImpls []string) {
	mustBeAdmin(cur)
	runtime.AssertOriginCall()
	impl = newImpl
	implPath = path
	allowedImpls = cloneStrings(newAllowedImpls)
}

func mustBeAdmin(cur realm) {
	if cur.Previous().Address() != core.GetAdmin() {
		panic("zkgm: admin only")
	}
}
