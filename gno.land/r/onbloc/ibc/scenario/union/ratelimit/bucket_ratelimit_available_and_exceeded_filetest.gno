// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/ratelimit
package ratelimit

// bucket_ratelimit_available_and_exceeded_filetest verifies the token-bucket rate
// limiter directly against a really-configured bucket. SetBucketConfig installs a
// capacity-100, refill-10/s bucket for a denom; the test then reads that bucket back
// (GetTokenBucket) and drives tokenbucket.RateLimit on it, asserting the two behaviours
// that matter: it returns ErrRateLimitExceeded when the requested amount exceeds the
// available tokens, and Available decreases as tokens are spent and increases again as
// the bucket refills over elapsed time.
//
// Time is the real chain clock: tokenbucket refills by (now - LastRefill), and the impl
// feeds it time.Now().Unix(). The bucket's LastRefill is stamped at SetBucketConfig, so
// the spends run at the same block (no refill), and the refill step advances the chain
// clock with testing.SkipHeights (5s per block) before reading time.Now() again — i.e.
// 10 seconds genuinely elapse rather than being asserted by a hand-picked timestamp.

import (
	"testing"
	"time"

	"gno.land/p/nt/ufmt/v0"

	u256 "gno.land/p/gnoswap/uint256"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const (
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	denom        = "ibc/rate-limited-denom"
)

func main(cur realm) {
	println("[SCENARIO] 1. Install the impl and configure a capacity-100, refill-10/s bucket")
	configure(cur)
	println("")

	bucket := mustBucket()
	ufmt.Printf("[INFO] configured bucket: capacity=%d available=%d refillRate=%d\n", bucket.Capacity.Uint64(), bucket.Available.Uint64(), bucket.RefillRate.Uint64())
	ufmt.Println("[EXPECTED] capacity=100 available=100 refillRate=10")
	println("")

	println("[SCENARIO] 2. Spend 70 at the current block: within capacity -> Available drops 100 -> 30")
	rateLimit(bucket, 70)
	println("")

	println("[SCENARIO] 3. Spend 70 again (same block): exceeds the 30 available -> ErrRateLimitExceeded, Available unchanged")
	rateLimit(bucket, 70)
	println("")

	println("[SCENARIO] 4. Spend the remaining 30 (same block) -> Available drops 30 -> 0")
	rateLimit(bucket, 30)
	println("")

	println("[SCENARIO] 5. Advance the chain 10s (SkipHeights), then spend 50: the bucket refilled -> Available 0 -> 50")
	testing.SkipHeights(2) // 2 blocks * 5s = 10s of real chain time
	rateLimit(bucket, 50)
}

func configure(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetBucketConfig(cross(cur), denom, u256.NewUint(100), u256.NewUint(10))
}

func mustBucket() *tb.TokenBucket {
	bucket, err := zkgm.GetTokenBucket(denom)
	if err != nil {
		panic(err)
	}
	return bucket
}

// rateLimit calls tokenbucket.RateLimit with the real chain time as `now` (matching the
// impl's rateLimit, which passes time.Now().Unix()), and reports the outcome and the
// resulting Available so both ErrRateLimitExceeded and the Available transition show.
func rateLimit(bucket *tb.TokenBucket, amount uint64) {
	before := bucket.Available.Uint64()
	err := bucket.RateLimit(u256.NewUint(amount), now())

	result := "ok"
	if err != nil {
		result = err.Error()
	}
	ufmt.Printf("[INFO] RateLimit(%d): result=%q, available %d -> %d\n", amount, result, before, bucket.Available.Uint64())
}

func now() *u256.Uint {
	return u256.NewUint(uint64(time.Now().Unix()))
}

// Output:
// [SCENARIO] 1. Install the impl and configure a capacity-100, refill-10/s bucket
//
// [INFO] configured bucket: capacity=100 available=100 refillRate=10
// [EXPECTED] capacity=100 available=100 refillRate=10
//
// [SCENARIO] 2. Spend 70 at the current block: within capacity -> Available drops 100 -> 30
// [INFO] RateLimit(70): result="ok", available 100 -> 30
//
// [SCENARIO] 3. Spend 70 again (same block): exceeds the 30 available -> ErrRateLimitExceeded, Available unchanged
// [INFO] RateLimit(70): result="tokenbucket: rate limit exceeded", available 30 -> 30
//
// [SCENARIO] 4. Spend the remaining 30 (same block) -> Available drops 30 -> 0
// [INFO] RateLimit(30): result="ok", available 30 -> 0
//
// [SCENARIO] 5. Advance the chain 10s (SkipHeights), then spend 50: the bucket refilled -> Available 0 -> 50
// [INFO] RateLimit(50): result="ok", available 0 -> 50
