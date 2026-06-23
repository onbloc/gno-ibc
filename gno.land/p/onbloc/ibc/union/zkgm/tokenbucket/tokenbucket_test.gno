package tokenbucket

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestNew(t *testing.T) {
	cases := []struct {
		name       string
		capacity   *u256.Uint
		refillRate *u256.Uint
		now        *u256.Uint
		wantErr    error
	}{
		{"rejects zero capacity", u256.Zero(), u256.NewUint(1), u256.Zero(), ZeroCapacity},
		{"rejects zero refill rate", u256.NewUint(1), u256.Zero(), u256.Zero(), ZeroRefillRate},
		{"initializes available and last refill", u256.NewUint(100), u256.NewUint(5), u256.NewUint(7), nil},
		{"clones inputs, does not alias", u256.NewUint(100), u256.NewUint(5), u256.NewUint(7), nil},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tb, err := New(tc.capacity, tc.refillRate, tc.now)
			if err != tc.wantErr {
				t.Fatalf("New error: got %v want %v", err, tc.wantErr)
			}
			if tc.wantErr != nil {
				return
			}

			assertUintEqual(t, "capacity", tb.Capacity, tc.capacity)
			assertUintEqual(t, "available", tb.Available, tc.capacity)
			assertUintEqual(t, "refill_rate", tb.RefillRate, tc.refillRate)
			assertUintEqual(t, "last_refill", tb.LastRefill, tc.now)

			// Mutate inputs to prove fields are cloned, not aliased
			tc.capacity.Set(u256.NewUint(999))
			tc.refillRate.Set(u256.NewUint(888))
			tc.now.Set(u256.NewUint(777))

			if tb.Capacity.Cmp(u256.NewUint(999)) == 0 {
				t.Fatalf("capacity was aliased, not cloned")
			}
			if tb.RefillRate.Cmp(u256.NewUint(888)) == 0 {
				t.Fatalf("refill_rate was aliased, not cloned")
			}
			if tb.LastRefill.Cmp(u256.NewUint(777)) == 0 {
				t.Fatalf("last_refill was aliased, not cloned")
			}
		})
	}
}

func TestRefill(t *testing.T) {
	cases := []struct {
		name           string
		capacity       uint64
		refillRate     uint64
		start          uint64
		initialCharge  uint64
		now            uint64
		wantAvailable  uint64
		wantLastRefill uint64
	}{
		{"adds elapsed capacity", 100, 5, 10, 80, 13, 35, 13},
		{"caps at capacity", 100, 50, 10, 80, 12, 100, 12},
		{"full bucket only moves last refill", 100, 5, 10, 0, 20, 100, 20},
		{"ignores clock going backward", 100, 5, 10, 80, 5, 20, 10},
		{"no-op when now equals last refill", 100, 5, 10, 40, 10, 60, 10},
		{"saturates at capacity with huge elapsed", 100, 1000, 10, 0, 15, 100, 15},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tb := mustNew(t, tc.capacity, tc.refillRate, tc.start)
			if tc.initialCharge != 0 {
				mustRateLimit(t, tb, tc.initialCharge, tc.start)
			}

			tb.Refill(u256.NewUint(tc.now))

			assertUint(t, "available", tb.Available, tc.wantAvailable)
			assertUint(t, "last_refill", tb.LastRefill, tc.wantLastRefill)
		})
	}
}

func TestRateLimit(t *testing.T) {
	cases := []struct {
		name           string
		initialCharge  uint64
		amount         uint64
		now            uint64
		wantErr        error
		wantAvailable  uint64
		wantLastRefill uint64
	}{
		{"allows within available", 0, 40, 10, nil, 60, 10},
		{"refills before charging", 80, 30, 12, nil, 0, 12},
		{"rejects exceeded amount", 0, 101, 10, RateLimitExceeded, 100, 10},
		{"zero amount noop", 0, 0, 20, nil, 100, 10},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tb := mustNew(t, 100, 5, 10)
			if tc.initialCharge != 0 {
				mustRateLimit(t, tb, tc.initialCharge, 10)
			}

			err := tb.RateLimit(u256.NewUint(tc.amount), u256.NewUint(tc.now))
			if err != tc.wantErr {
				t.Fatalf("RateLimit error: got %v want %v", err, tc.wantErr)
			}

			assertUint(t, "available", tb.Available, tc.wantAvailable)
			assertUint(t, "last_refill", tb.LastRefill, tc.wantLastRefill)
		})
	}
}

func TestUpdate(t *testing.T) {
	cases := []struct {
		name           string
		start          uint64
		initialCharge  uint64
		capacity       *u256.Uint
		refillRate     *u256.Uint
		reset          bool
		wantErr        error
		wantCapacity   uint64
		wantAvailable  uint64
		wantRefillRate uint64
	}{
		{"rejects zero capacity, preserves state", 10, 40, u256.Zero(), u256.NewUint(1), false, ZeroCapacity, 100, 60, 5},
		{"rejects zero refill rate, preserves state", 10, 40, u256.NewUint(1), u256.Zero(), false, ZeroRefillRate, 100, 60, 5},
		{"without reset keeps available", 10, 40, u256.NewUint(200), u256.NewUint(7), false, nil, 200, 60, 7},
		{"with reset restores available", 10, 40, u256.NewUint(200), u256.NewUint(7), true, nil, 200, 200, 7},
		{"clamps available when shrinking capacity", 10, 0, u256.NewUint(50), u256.NewUint(5), false, nil, 50, 50, 5},
		{"last refill zero restores available", 0, 40, u256.NewUint(200), u256.NewUint(7), false, nil, 200, 200, 7},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tb := mustNew(t, 100, 5, tc.start)
			if tc.initialCharge != 0 {
				mustRateLimit(t, tb, tc.initialCharge, tc.start)
			}

			err := tb.Update(tc.capacity, tc.refillRate, tc.reset)
			if err != tc.wantErr {
				t.Fatalf("Update error: got %v want %v", err, tc.wantErr)
			}
			if tc.wantErr != nil {
				// Verify state was preserved on error
				assertUint(t, "capacity", tb.Capacity, tc.wantCapacity)
				assertUint(t, "available", tb.Available, tc.wantAvailable)
				assertUint(t, "refill_rate", tb.RefillRate, tc.wantRefillRate)
				return
			}

			assertUint(t, "capacity", tb.Capacity, tc.wantCapacity)
			assertUint(t, "available", tb.Available, tc.wantAvailable)
			assertUint(t, "refill_rate", tb.RefillRate, tc.wantRefillRate)
		})
	}
}

func TestSaturatingAdd(t *testing.T) {
	max := maxUint256()
	cases := []struct {
		name string
		x    *u256.Uint
		y    *u256.Uint
		want *u256.Uint
	}{
		{"adds without overflow", u256.NewUint(5), u256.NewUint(7), u256.NewUint(12)},
		{"saturates on overflow", max, u256.NewUint(1), max},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := saturatingAdd(tc.x, tc.y)
			assertUintEqual(t, "sum", got, tc.want)
		})
	}
}

func TestSaturatingMul(t *testing.T) {
	max := maxUint256()
	cases := []struct {
		name string
		x    *u256.Uint
		y    *u256.Uint
		want *u256.Uint
	}{
		{"multiplies without overflow", u256.NewUint(6), u256.NewUint(7), u256.NewUint(42)},
		{"saturates on overflow", max, u256.NewUint(2), max},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := saturatingMul(tc.x, tc.y)
			assertUintEqual(t, "product", got, tc.want)
		})
	}
}

func TestMin(t *testing.T) {
	cases := []struct {
		name string
		x    *u256.Uint
		y    *u256.Uint
		want *u256.Uint
	}{
		{"returns x when x is lower", u256.NewUint(3), u256.NewUint(5), u256.NewUint(3)},
		{"returns x when equal", u256.NewUint(5), u256.NewUint(5), u256.NewUint(5)},
		{"returns y when y is lower", u256.NewUint(8), u256.NewUint(2), u256.NewUint(2)},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := min(tc.x, tc.y)
			assertUintEqual(t, "min", got, tc.want)

			got.Set(u256.NewUint(99))
			if tc.x.Cmp(u256.NewUint(99)) == 0 || tc.y.Cmp(u256.NewUint(99)) == 0 {
				t.Fatalf("min returned an aliased uint")
			}
		})
	}
}

func assertUint(t *testing.T, name string, got *u256.Uint, want uint64) {
	t.Helper()

	wantUint := u256.NewUint(want)
	if got.Cmp(wantUint) != 0 {
		t.Fatalf("%s: got %s want %s", name, got.ToString(), wantUint.ToString())
	}
}
