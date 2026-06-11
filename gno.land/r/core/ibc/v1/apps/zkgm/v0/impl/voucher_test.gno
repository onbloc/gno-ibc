package impl

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestAmountInt64Zero(t *testing.T) {
	got, err := amountInt64(u256.NewUint(0))
	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), got)
}

func TestAmountInt64MaxInt64(t *testing.T) {
	got, err := amountInt64(u256.NewUint(uint64(math.MaxInt64)))
	uassert.NoError(t, err)
	uassert.Equal(t, int64(math.MaxInt64), got)
}

func TestAmountInt64RejectsMaxInt64PlusOne(t *testing.T) {
	_, err := amountInt64(u256.NewUint(uint64(math.MaxInt64) + 1))
	uassert.Error(t, err)
}

func TestAmountInt64RejectsMaxUint64(t *testing.T) {
	_, err := amountInt64(u256.NewUint(math.MaxUint64))
	uassert.Error(t, err)
}

func TestAmountInt64RejectsWideValue(t *testing.T) {
	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
	_, err := amountInt64(wide)
	uassert.Error(t, err)
}
