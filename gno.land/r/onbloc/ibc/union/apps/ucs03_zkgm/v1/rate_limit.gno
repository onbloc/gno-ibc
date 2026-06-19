package impl

import (
	"time"

	u256 "gno.land/p/gnoswap/uint256"
)

// rateLimit charges `amount` from denom's token bucket when rate limiting is
// enabled. The bucket is anchored to block time, so its RefillRate is tokens per
// second. A missing bucket means the denom is unlimited.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3218-L3237
func (v *ucs03ZkgmV1) rateLimit(_ int, rlm realm, denom string, amount *u256.Uint) error {
	if v.store.RateLimitDisabled() || amount == nil {
		return nil
	}

	bucket, ok := v.store.GetTokenBucket(denom)
	if !ok || bucket == nil {
		return nil
	}

	now := time.Now().Unix()

	return bucket.RateLimit(amount, u256.NewUint(uint64(now)))
}
