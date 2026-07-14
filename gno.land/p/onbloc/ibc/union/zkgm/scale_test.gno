package zkgm

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestPow10(t *testing.T) {
	uassert.Equal(t, "1", Pow10(0).ToString())
	uassert.Equal(t, "10", Pow10(1).ToString())
	uassert.Equal(t, "1000000", Pow10(6).ToString())
	uassert.Equal(t, "1000000000000", Pow10(12).ToString())
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
