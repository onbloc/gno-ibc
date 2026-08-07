package zkgm

import (
	"math"
	"testing"

	"gno.land/p/nt/uassert/v0"
	u256 "gno.land/p/onbloc/math/uint256"
)

func TestPow10(t *testing.T) {
	uassert.Equal(t, "0", Pow10(-1).ToString())
	uassert.Equal(t, "1", Pow10(0).ToString())
	uassert.Equal(t, "10", Pow10(1).ToString())
	uassert.Equal(t, "1000000", Pow10(6).ToString())
	uassert.Equal(t, "1000000000000", Pow10(12).ToString())
}

func TestPow10BeyondUint64DoesNotSaturate(t *testing.T) {
	// 10^19 is the largest power of ten that still fits in a uint64
	// (max uint64 ~= 1.8e19); 10^20 is the first that overflows it.
	// A float64 intermediate (math.Pow10 + uint64 conversion) saturates
	// around 2^63 past this point instead of erroring, so this asserts
	// the exact integer value instead.
	uassert.Equal(t, "10000000000000000000", Pow10(19).ToString())
	uassert.Equal(t, "100000000000000000000", Pow10(20).ToString())
	uassert.Equal(t, "10000000000000000000000000000000000000000", Pow10(40).ToString())
}

func TestScaleDownToInt64(t *testing.T) {
	// 1e18 with a 12-digit scale downscales to 1e6.
	wire1e18 := u256.Zero().Mul(u256.NewUint(1000000000000), u256.NewUint(1000000))

	cases := []struct {
		name     string
		scaleExp int
		amount   *u256.Uint
		want     int64
		wantErr  error
	}{
		{"identity zero exp passes through", 0, u256.NewUint(42), 42, nil},
		{"identity max int64", 0, u256.NewUint(uint64(math.MaxInt64)), math.MaxInt64, nil},
		{"identity overflow int64", 0, u256.NewUint(uint64(math.MaxInt64) + 1), 0, ErrAmountOverflow},
		{"downscale 1e18 by 12 -> 1e6", 12, wire1e18, 1000000, nil},
		{"downscale 1e20 by 20 -> 1", 20, u256.MustFromDecimal("100000000000000000000"), 1, nil},
		{"downscale exact multiple", 6, u256.NewUint(77000000), 77, nil},
		{"downscale indivisible dust", 6, u256.NewUint(77000001), 0, ErrAmountNotDivisible},
		{"downscale below one unit", 12, u256.NewUint(999999999999), 0, ErrAmountNotDivisible},
		{"downscaled quotient still overflows", 0, u256.Zero().Lsh(u256.NewUint(1), 64), 0, ErrAmountOverflow},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ScaleDownToInt64(tc.amount, tc.scaleExp)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}

			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, got)
		})
	}
}

func TestScaleDownDoesNotMutateInput(t *testing.T) {
	amount := u256.NewUint(5000000)
	_, err := ScaleDownToInt64(amount, 6)
	uassert.NoError(t, err)
	// The divisor/quotient use fresh receivers, so the caller's amount is intact.
	uassert.Equal(t, "5000000", amount.ToString())
}
