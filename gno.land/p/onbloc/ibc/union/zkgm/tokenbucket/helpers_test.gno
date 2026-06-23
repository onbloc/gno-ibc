package tokenbucket

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

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

func assertUintEqual(t *testing.T, name string, got *u256.Uint, want *u256.Uint) {
	t.Helper()

	if got.Cmp(want) != 0 {
		t.Fatalf("%s: got %s want %s", name, got.ToString(), want.ToString())
	}
}

func maxUint256() *u256.Uint {
	return new(u256.Uint).SetAllOne()
}
