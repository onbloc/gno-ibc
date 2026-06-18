package impl

import (
	"chain"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestFundsSubDeductsExactDenom(t *testing.T) {
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 100)))
	uassert.NoError(t, f.sub("ugnot", u256.NewUint(100)))
	uassert.True(t, f.isEmpty())
}

func TestFundsSubPartialLeavesRemainder(t *testing.T) {
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 10)))
	uassert.NoError(t, f.sub("ugnot", u256.NewUint(4)))
	uassert.False(t, f.isEmpty())
}

func TestFundsSubInsufficientErrors(t *testing.T) {
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 10)))
	uassert.Error(t, f.sub("ugnot", u256.NewUint(11)))
}

func TestFundsSubUnknownDenomErrors(t *testing.T) {
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 10)))
	uassert.Error(t, f.sub("uatom", u256.NewUint(1)))
}

func TestFundsSubOverflowAmountErrors(t *testing.T) {
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 1)))
	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
	uassert.Error(t, f.sub("ugnot", wide))
}

func TestFundsAssertEmptyRejectsLeftover(t *testing.T) {
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 10)))
	uassert.NoError(t, f.sub("ugnot", u256.NewUint(4)))
	uassert.Error(t, f.assertEmpty())
}

func TestFundsEmptyIsEmpty(t *testing.T) {
	f := newFunds(nil)
	uassert.True(t, f.isEmpty())
	uassert.NoError(t, f.assertEmpty())
}
