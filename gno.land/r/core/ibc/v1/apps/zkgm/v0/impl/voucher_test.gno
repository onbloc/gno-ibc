package impl

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestAmountInt64(t *testing.T) {
	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
	cases := []struct {
		name    string
		input   *u256.Uint
		want    int64
		wantErr bool
	}{
		{"zero", u256.NewUint(0), 0, false},
		{"max int64", u256.NewUint(uint64(math.MaxInt64)), math.MaxInt64, false},
		{"max int64 + 1", u256.NewUint(uint64(math.MaxInt64) + 1), 0, true},
		{"max uint64", u256.NewUint(math.MaxUint64), 0, true},
		{"wide (> 64 bits)", wide, 0, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := amountInt64(tc.input)
			if tc.wantErr {
				uassert.Error(t, err)
			} else {
				uassert.NoError(t, err)
				uassert.Equal(t, tc.want, got)
			}
		})
	}
}
