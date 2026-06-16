package tokenbucket

import (
	"errors"

	u256 "gno.land/p/gnoswap/uint256"
)

var (
	ZeroCapacity      = errors.New("token bucket capacity must not be zero")
	ZeroRefillRate    = errors.New("token bucket refill rate must not be zero")
	RateLimitExceeded = errors.New("token bucket rate limit exceeded")
)

type TokenBucket struct {
	Capacity   *u256.Uint
	Available  *u256.Uint
	RefillRate *u256.Uint
	LastRefill *u256.Uint
}

func New(capacity *u256.Uint, refillRate *u256.Uint, now *u256.Uint) (*TokenBucket, error) {
	if capacity.IsZero() {
		return nil, ZeroCapacity
	}
	if refillRate.IsZero() {
		return nil, ZeroRefillRate
	}

	return &TokenBucket{
		Capacity:   capacity.Clone(),
		Available:  capacity.Clone(),
		RefillRate: refillRate.Clone(),
		LastRefill: now.Clone(),
	}, nil
}

func (tb *TokenBucket) Refill(now *u256.Uint) {
	if now.Lte(tb.LastRefill) {
		return
	}
	if tb.Available.Gte(tb.Capacity) {
		tb.LastRefill.Set(now)
		return
	}

	elapsed := new(u256.Uint).Sub(now, tb.LastRefill)
	toRefill := saturatingMul(tb.RefillRate, elapsed)
	tb.Available = min(tb.Capacity, saturatingAdd(tb.Available, toRefill))
	tb.LastRefill.Set(now)
}

func (tb *TokenBucket) RateLimit(amount *u256.Uint, now *u256.Uint) error {
	if amount.IsZero() {
		return nil
	}

	tb.Refill(now)
	if tb.Available.Lt(amount) {
		return RateLimitExceeded
	}

	tb.Available.Sub(tb.Available, amount)
	return nil
}

func (tb *TokenBucket) Update(capacity *u256.Uint, refillRate *u256.Uint, reset bool) error {
	if capacity.IsZero() {
		return ZeroCapacity
	}
	if refillRate.IsZero() {
		return ZeroRefillRate
	}

	tb.Capacity = capacity.Clone()
	tb.RefillRate = refillRate.Clone()
	if tb.LastRefill.IsZero() || reset {
		tb.Available = tb.Capacity.Clone()
	} else if tb.Available.Gt(tb.Capacity) {
		tb.Available = tb.Capacity.Clone()
	}
	return nil
}

func saturatingAdd(x *u256.Uint, y *u256.Uint) *u256.Uint {
	z, overflow := new(u256.Uint).AddOverflow(x, y)
	if overflow {
		return new(u256.Uint).SetAllOne()
	}
	return z
}

func saturatingMul(x *u256.Uint, y *u256.Uint) *u256.Uint {
	z, overflow := new(u256.Uint).MulOverflow(x, y)
	if overflow {
		return new(u256.Uint).SetAllOne()
	}
	return z
}

func min(x *u256.Uint, y *u256.Uint) *u256.Uint {
	if x.Lte(y) {
		return x.Clone()
	}
	return y.Clone()
}
