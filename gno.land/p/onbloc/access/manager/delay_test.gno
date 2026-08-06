package manager

import "testing"

// Union: https://github.com/unionlabs/union/blob/951fe1f7d2e8c136edbf44251fc98feefeabc35d/lib/access-manager-types/src/time.rs#L180-L195
func TestNewDelay(t *testing.T) {
	now := NewTimePoint(1_000_000)

	tests := []struct {
		name  string
		delay uint32
	}{
		{"zero", 0},
		{"non-zero", 42},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			delay := NewDelay(tc.delay)

			if delay != (Delay{EffectDate: 0, ValueBefore: 0, ValueAfter: tc.delay}) {
				t.Fatalf("NewDelay(%d) = %+v", tc.delay, delay)
			}
			if got := delay.Get(now); got != tc.delay {
				t.Fatalf("Get() = %d, want %d", got, tc.delay)
			}
		})
	}
}

// Union: https://github.com/unionlabs/union/blob/951fe1f7d2e8c136edbf44251fc98feefeabc35d/lib/access-manager-types/src/time.rs#L197-L235
func TestDelayGet(t *testing.T) {
	now := NewTimePoint(1_000_000)
	const valueBefore, valueAfter uint32 = 24_194, 4_214_143

	tests := []struct {
		name string
		at   TimePoint
		want uint32
	}{
		{"effect in the past returns after", NewTimePoint(now.Int64() - 1), valueAfter},
		{"effect at now returns after", now, valueAfter},
		{"effect in the future returns before", NewTimePoint(now.Int64() + 1), valueBefore},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			delay := Delay{EffectDate: tc.at, ValueBefore: valueBefore, ValueAfter: valueAfter}
			if got := delay.Get(now); got != tc.want {
				t.Fatalf("Get() = %d, want %d", got, tc.want)
			}
		})
	}
}

// TestDelayWithUpdate mirrors OpenZeppelin's Delay.withUpdate / Union's
// Delay::with_update: the setback is the minimum setback, floored up to the
// amount by which a decrease shrinks the active value. Both an increase and
// a decrease smaller than minSetback still wait the full minSetback -- this
// is the load-bearing invariant behind the fix: an admin cannot shrink an
// active grant delay and have the smaller value apply to a grant made in
// the same instant.
// Union: https://github.com/unionlabs/union/blob/951fe1f7d2e8c136edbf44251fc98feefeabc35d/lib/access-manager-types/src/time.rs#L237-L280
func TestDelayWithUpdate(t *testing.T) {
	now := NewTimePoint(1_000_000)
	const active, minSetback uint32 = 1_000, 100

	tests := []struct {
		name        string
		newDelay    uint32
		wantSetback uint32
	}{
		{"increase waits minSetback", active + 1, minSetback},
		{"equal value waits minSetback", active, minSetback},
		{"small decrease waits minSetback", active - 1, minSetback},
		{"decrease smaller than minSetback waits minSetback", active - minSetback + 1, minSetback},
		{"decrease equal to minSetback waits minSetback", active - minSetback, minSetback},
		{"decrease larger than minSetback waits the full decrease", active - minSetback - 1, minSetback + 1},
		{"decrease to zero waits the full decrease", 0, active},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			delay := NewDelay(active)

			updated, effect := delay.WithUpdate(now, tc.newDelay, minSetback)

			wantEffect := NewTimePoint(now.Int64() + int64(tc.wantSetback))
			if !effect.Equal(wantEffect) {
				t.Fatalf("effect = %s, want %s", effect, wantEffect)
			}
			if updated.EffectDate != wantEffect {
				t.Fatalf("updated.EffectDate = %s, want %s", updated.EffectDate, wantEffect)
			}
			if updated.ValueBefore != active {
				t.Fatalf("updated.ValueBefore = %d, want %d (the value active at now)", updated.ValueBefore, active)
			}
			if updated.ValueAfter != tc.newDelay {
				t.Fatalf("updated.ValueAfter = %d, want %d", updated.ValueAfter, tc.newDelay)
			}

			if got := updated.Get(now); got != active {
				t.Fatalf("Get(now) before effect = %d, want %d", got, active)
			}
			if got := updated.Get(NewTimePoint(wantEffect.Int64() - 1)); got != active {
				t.Fatalf("Get(effect-1) = %d, want %d", got, active)
			}
			if got := updated.Get(wantEffect); got != tc.newDelay {
				t.Fatalf("Get(effect) = %d, want %d", got, tc.newDelay)
			}
		})
	}
}

// TestDelayWithUpdateAgainstPendingValue confirms WithUpdate reads the
// currently-active value through Get before recomputing the setback, so
// updating a Delay that already has a pending change in the future still
// enforces the setback against the value active right now, not the pending
// one.
func TestDelayWithUpdateAgainstPendingValue(t *testing.T) {
	now := NewTimePoint(1_000_000)
	pending := Delay{EffectDate: NewTimePoint(now.Int64() + 500), ValueBefore: 10, ValueAfter: 1_000}

	updated, effect := pending.WithUpdate(now, 0, MinSetback)

	wantEffect := NewTimePoint(now.Int64() + int64(MinSetback))
	if !effect.Equal(wantEffect) {
		t.Fatalf("effect = %s, want %s (based on the active value 10, not the pending 1000)", effect, wantEffect)
	}
	if updated.ValueBefore != 10 {
		t.Fatalf("updated.ValueBefore = %d, want 10", updated.ValueBefore)
	}
}
