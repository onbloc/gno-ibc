package tokenbucket

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestNewRejectsZeroCapacity(t *testing.T) {
	_, err := New(u256.Zero(), u256.NewUint(1), u256.Zero())
	if err != ZeroCapacity {
		t.Fatalf("New zero capacity error: got %v want %v", err, ZeroCapacity)
	}
}

func TestNewRejectsZeroRefillRate(t *testing.T) {
	_, err := New(u256.NewUint(1), u256.Zero(), u256.Zero())
	if err != ZeroRefillRate {
		t.Fatalf("New zero refill rate error: got %v want %v", err, ZeroRefillRate)
	}
}

func TestNewInitializesAvailableAndLastRefill(t *testing.T) {
	tb := mustNew(t, 100, 5, 7)

	assertUint(t, "capacity", tb.Capacity, 100)
	assertUint(t, "available", tb.Available, 100)
	assertUint(t, "refill_rate", tb.RefillRate, 5)
	assertUint(t, "last_refill", tb.LastRefill, 7)
}

func TestRefillAddsElapsedCapacity(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)
	mustRateLimit(t, tb, 80, 10)

	tb.Refill(u256.NewUint(13))

	assertUint(t, "available", tb.Available, 35)
	assertUint(t, "last_refill", tb.LastRefill, 13)
}

func TestRefillCapsAtCapacity(t *testing.T) {
	tb := mustNew(t, 100, 50, 10)
	mustRateLimit(t, tb, 80, 10)

	tb.Refill(u256.NewUint(12))

	assertUint(t, "available", tb.Available, 100)
	assertUint(t, "last_refill", tb.LastRefill, 12)
}

func TestRefillFullBucketOnlyMovesLastRefill(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)

	tb.Refill(u256.NewUint(20))

	assertUint(t, "available", tb.Available, 100)
	assertUint(t, "last_refill", tb.LastRefill, 20)
}

func TestRateLimitAllowsWithinAvailable(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)

	mustRateLimit(t, tb, 40, 10)

	assertUint(t, "available", tb.Available, 60)
	assertUint(t, "last_refill", tb.LastRefill, 10)
}

func TestRateLimitRefillsBeforeCharging(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)
	mustRateLimit(t, tb, 80, 10)

	mustRateLimit(t, tb, 30, 12)

	assertUint(t, "available", tb.Available, 0)
	assertUint(t, "last_refill", tb.LastRefill, 12)
}

func TestRateLimitRejectsExceededAmount(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)

	err := tb.RateLimit(u256.NewUint(101), u256.NewUint(10))
	if err != RateLimitExceeded {
		t.Fatalf("RateLimit exceeded error: got %v want %v", err, RateLimitExceeded)
	}

	assertUint(t, "available", tb.Available, 100)
}

func TestRateLimitZeroAmountNoop(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)

	if err := tb.RateLimit(u256.Zero(), u256.NewUint(20)); err != nil {
		t.Fatalf("RateLimit zero amount error: %v", err)
	}

	assertUint(t, "available", tb.Available, 100)
	assertUint(t, "last_refill", tb.LastRefill, 10)
}

func TestUpdateRejectsZeroCapacity(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)

	err := tb.Update(u256.Zero(), u256.NewUint(1), false)
	if err != ZeroCapacity {
		t.Fatalf("Update zero capacity error: got %v want %v", err, ZeroCapacity)
	}
}

func TestUpdateRejectsZeroRefillRate(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)

	err := tb.Update(u256.NewUint(1), u256.Zero(), false)
	if err != ZeroRefillRate {
		t.Fatalf("Update zero refill rate error: got %v want %v", err, ZeroRefillRate)
	}
}

func TestUpdateWithoutResetKeepsAvailable(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)
	mustRateLimit(t, tb, 40, 10)

	if err := tb.Update(u256.NewUint(200), u256.NewUint(7), false); err != nil {
		t.Fatalf("Update error: %v", err)
	}

	assertUint(t, "capacity", tb.Capacity, 200)
	assertUint(t, "available", tb.Available, 60)
	assertUint(t, "refill_rate", tb.RefillRate, 7)
}

func TestUpdateWithResetRestoresAvailable(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)
	mustRateLimit(t, tb, 40, 10)

	if err := tb.Update(u256.NewUint(200), u256.NewUint(7), true); err != nil {
		t.Fatalf("Update error: %v", err)
	}

	assertUint(t, "capacity", tb.Capacity, 200)
	assertUint(t, "available", tb.Available, 200)
	assertUint(t, "refill_rate", tb.RefillRate, 7)
}

func TestRefillIgnoresClockGoingBackward(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)
	mustRateLimit(t, tb, 80, 10)

	tb.Refill(u256.NewUint(5))

	assertUint(t, "available", tb.Available, 20)
	assertUint(t, "last_refill", tb.LastRefill, 10)
}

func TestUpdateClampsAvailableWhenShrinkingCapacity(t *testing.T) {
	tb := mustNew(t, 100, 5, 10)

	if err := tb.Update(u256.NewUint(50), u256.NewUint(5), false); err != nil {
		t.Fatalf("Update error: %v", err)
	}

	assertUint(t, "capacity", tb.Capacity, 50)
	assertUint(t, "available", tb.Available, 50)
}

func TestUpdateWhenLastRefillZeroRestoresAvailable(t *testing.T) {
	tb := mustNew(t, 100, 5, 0)
	mustRateLimit(t, tb, 40, 0)

	if err := tb.Update(u256.NewUint(200), u256.NewUint(7), false); err != nil {
		t.Fatalf("Update error: %v", err)
	}

	assertUint(t, "available", tb.Available, 200)
}

func mustNew(t *testing.T, capacity uint64, refillRate uint64, now uint64) *TokenBucket {
	t.Helper()

	tb, err := New(u256.NewUint(capacity), u256.NewUint(refillRate), u256.NewUint(now))
	if err != nil {
		t.Fatalf("New error: %v", err)
	}
	return tb
}

func mustRateLimit(t *testing.T, tb *TokenBucket, amount uint64, now uint64) {
	t.Helper()

	if err := tb.RateLimit(u256.NewUint(amount), u256.NewUint(now)); err != nil {
		t.Fatalf("RateLimit error: %v", err)
	}
}

func assertUint(t *testing.T, name string, got *u256.Uint, want uint64) {
	t.Helper()

	wantUint := u256.NewUint(want)
	if got.Cmp(wantUint) != 0 {
		t.Fatalf("%s: got %s want %s", name, got.ToString(), wantUint.ToString())
	}
}
