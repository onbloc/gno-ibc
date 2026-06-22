package zkgm

import (
	"time"

	u256 "gno.land/p/gnoswap/uint256"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

// SetBucketConfig creates or updates the per-denom send-side rate-limit bucket.
// The bucket is anchored to block time, so RefillRate is tokens per second.
func SetBucketConfig(cur realm, denom string, capacity *u256.Uint, refillRate *u256.Uint) {
	assertIsAdmin(cur)

	bucket, ok := store.GetTokenBucket(denom)
	if !ok {
		newBucket, err := tb.New(capacity, refillRate, u256.NewUint(uint64(time.Now().Unix())))
		if err != nil {
			panic(err)
		}

		store.SetTokenBucket(0, cur, denom, newBucket)

		return
	}

	err := bucket.Update(capacity, refillRate, false)
	if err != nil {
		panic(err)
	}
}

// SetRateLimitDisabled toggles the global rate-limit kill switch.
func SetRateLimitDisabled(cur realm, disabled bool) {
	assertIsAdmin(cur)
	store.SetRateLimitDisabled(0, cur, disabled)
}

// Pausable toggles the global pause gate checked by every App receiver.
func Pausable(cur realm, p bool) {
	assertIsAdmin(cur)

	paused = p
}
