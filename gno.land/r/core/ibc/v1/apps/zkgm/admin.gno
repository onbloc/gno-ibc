package zkgm

import (
	"chain/runtime"

	tb "gno.land/p/onbloc/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/onbloc/unionibc/v1/core"
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
	runtime.AssertOriginCall()
	rateLimitDisabled = disabled
}

// ForceSetImpl forcibly replaces the registered implementation.
//
// Unlike UpdateImpl, ForceSetImpl bypasses implementation-allowlist checks and
// is intended only for administrative recovery when the registered
// implementation can no longer upgrade itself.
//
// implPath is not updated here; the new impl must call UpdateImpl after this
// to register its path via the runtime-verified caller identity. Include the
// new impl's pkg path in newAllowedImpls so it can make that call.
//
// AssertOriginCall is intentionally omitted: ZkgmImpl cannot be passed via
// maketx, so callers must route through an ephemeral realm, which would cause
// AssertOriginCall to always panic.
//
// Passing nil for newAllowedImpls clears the allowlist.
func ForceSetImpl(cur realm, newImpl ZkgmImpl, newAllowedImpls []string) {
	mustBeAdmin(cur)
	impl = newImpl
	allowedImpls = cloneStrings(newAllowedImpls)
}

func mustBeAdmin(cur realm) {
	if cur.Previous().Address() != core.GetAdmin() {
		panic("zkgm: admin only")
	}
}
