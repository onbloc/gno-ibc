package zkgm

import (
	"chain/runtime"

	u256 "gno.land/p/gnoswap/uint256"
	tb "gno.land/p/onbloc/ibc/zkgm/tokenbucket"
	core "gno.land/r/onbloc/ibc/core"
)

func Pause(cur realm) {
	mustBeAdmin(cur)
	runtime.AssertOriginCall()
	paused = true
	emitZkgmPausedEvent(core.GetAdmin())
}

func Unpause(cur realm) {
	mustBeAdmin(cur)
	runtime.AssertOriginCall()
	paused = false
	emitZkgmUnpausedEvent(core.GetAdmin())
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
		emitZkgmRateLimitBucketConfiguredEvent(core.GetAdmin(), denom, capacity, refillRate)
		return
	}

	if err := bucket.Update(capacity, refillRate, false); err != nil {
		panic(err)
	}
	emitZkgmRateLimitBucketConfiguredEvent(core.GetAdmin(), denom, capacity, refillRate)
}

// SetRateLimitDisabled toggles the global rate-limit kill switch. Admin-only.
func SetRateLimitDisabled(cur realm, disabled bool) {
	mustBeAdmin(cur)
	runtime.AssertOriginCall()
	rateLimitDisabled = disabled
	emitZkgmRateLimitDisabledSetEvent(core.GetAdmin(), disabled)
}

// ForceSetImpl forcibly replaces the registered implementation.
//
// Unlike UpdateImpl, ForceSetImpl bypasses implementation-allowlist checks and
// is intended only for administrative recovery when the registered
// implementation can no longer upgrade itself.
//
// implPath is cleared, not set. The admin cannot prove which realm owns
// newImpl, so binding implPath here would let a mistyped path grant escrow
// rights to an arbitrary realm. Clearing it immediately deauthorizes the
// displaced impl. The new impl rebinds implPath itself by calling UpdateImpl
// from its own realm, and its pkg path must therefore be present in
// newAllowedImpls. Until it runs, the new impl operates solely via
// newAllowedImpls membership and ImplPath()/GetConfig() honestly report "".
//
// A non-nil impl with an empty allowlist is rejected: it would be installed for
// dispatch yet unable to pass any fund or state gate and unable to self-register
// unless it is a trusted proxy subpackage bootstrap caller. Pass newImpl == nil
// to intentionally clear the impl.
//
// AssertOriginCall is intentionally omitted: ZkgmImpl cannot be passed via
// maketx, so callers must route through an ephemeral realm, which would cause
// AssertOriginCall to always panic.
func ForceSetImpl(cur realm, newImpl ZkgmImpl, newAllowedImpls []string) {
	mustBeAdmin(cur)
	if newImpl != nil && len(newAllowedImpls) == 0 {
		panic("zkgm: ForceSetImpl with a non-nil impl requires a non-empty allowlist")
	}
	oldImplPath := implPath
	impl = newImpl
	implPath = ""
	allowedImpls = cloneStrings(newAllowedImpls)
	emitZkgmImplForceSetEvent(core.GetAdmin(), oldImplPath, newImpl == nil, allowedImpls)
}

func mustBeAdmin(cur realm) {
	if cur.Previous().Address() != core.GetAdmin() {
		panic("zkgm: admin only")
	}
}
