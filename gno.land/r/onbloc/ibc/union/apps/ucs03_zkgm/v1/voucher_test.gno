package impl

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
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

func TestVoucherNameFallsBackToIBCDenom(cur realm, t *testing.T) {
	v := newTestImpl()

	ibcDenom := "ibc/name-fallback"
	rx := testAddress("name-fb-rx")

	uassert.NoError(t, v.mintVoucher(cur, ibcDenom, [32]byte{}, "", "SYM", 0, rx, u256.NewUint(1)))

	vou, ok := zkgm.Store().GetVoucher(ibcDenom)
	uassert.True(t, ok)
	uassert.Equal(t, ibcDenom, vou.Token().GetName())
}
