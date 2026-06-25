package impl

import (
	"chain"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

// parseCoins: well-formed inputs, the empty/blank edge cases, and malformed
// shapes that abort before coin construction.
func TestParseCoins(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		input     string
		want      chain.Coins
		wantPanic string
	}{
		{"empty string", "", nil, ""},
		{"single coin", "100ugnot", chain.NewCoins(chain.NewCoin("ugnot", 100)), ""},
		{
			"multiple coins",
			"100ugnot,50uatom",
			chain.NewCoins(chain.NewCoin("ugnot", 100), chain.NewCoin("uatom", 50)),
			"",
		},
		{"trailing comma skips empty part", "100ugnot,", chain.NewCoins(chain.NewCoin("ugnot", 100)), ""},
		{"leading comma skips empty part", ",100ugnot", chain.NewCoins(chain.NewCoin("ugnot", 100)), ""},
		{"zero amount", "0ugnot", chain.NewCoins(chain.NewCoin("ugnot", 0)), ""},
		{"missing amount", "ugnot", nil, "zkgm/coins: invalid coin"},
		{"missing denom", "100", nil, "zkgm/coins: invalid coin"},
		{"missing amount in second part", "100ugnot,uatom", nil, "zkgm/coins: invalid coin"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.wantPanic != "" {
				uassert.PanicsContains(t, cur, tc.wantPanic, func() {
					parseCoins(tc.input)
				})
				return
			}
			got := parseCoins(tc.input)
			uassert.Equal(t, tc.want.String(), got.String())
		})
	}
}

func TestNewFunds(t *testing.T) {
	sent := chain.NewCoins(chain.NewCoin("ugnot", 10))
	f := newFunds(sent)

	f.coins[0].Amount = 4

	uassert.Equal(t, int64(10), sent[0].Amount)
	uassert.Equal(t, int64(4), f.coins[0].Amount)
}

// funds.sub mirrors the reference contract's funds.sub(coin): it deducts a
// denom's amount, erroring on insufficient balance, unknown denom, or an amount
// that overflows int64.
func TestFundsSub(t *testing.T) {
	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
	cases := []struct {
		name      string
		have      chain.Coins
		denom     string
		amount    *u256.Uint
		wantErr   bool
		wantEmpty bool // only checked when wantErr is false
	}{
		{"exact deduct empties", chain.NewCoins(chain.NewCoin("ugnot", 100)), "ugnot", u256.NewUint(100), false, true},
		{"partial leaves remainder", chain.NewCoins(chain.NewCoin("ugnot", 10)), "ugnot", u256.NewUint(4), false, false},
		{"zero deduct is noop", chain.NewCoins(chain.NewCoin("ugnot", 10)), "ugnot", u256.Zero(), false, false},
		{"zero deduct on empty stays empty", chain.NewCoins(chain.NewCoin("ugnot", 0)), "ugnot", u256.Zero(), false, true},
		{"insufficient errors", chain.NewCoins(chain.NewCoin("ugnot", 10)), "ugnot", u256.NewUint(11), true, false},
		{"unknown denom errors", chain.NewCoins(chain.NewCoin("ugnot", 10)), "uatom", u256.NewUint(1), true, false},
		{"empty funds errors", nil, "ugnot", u256.NewUint(1), true, false},
		{"amount over int64 errors", chain.NewCoins(chain.NewCoin("ugnot", 1)), "ugnot", wide, true, false},
		{
			"deducts only target denom in multi-coin",
			chain.NewCoins(chain.NewCoin("ugnot", 100), chain.NewCoin("uatom", 50)),
			"ugnot", u256.NewUint(100), false, false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := newFunds(tc.have)
			err := f.sub(tc.denom, tc.amount)
			if tc.wantErr {
				uassert.Error(t, err)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.wantEmpty, f.isEmpty())
		})
	}
}

func TestFundsIsEmpty(t *testing.T) {
	cases := []struct {
		name string
		have chain.Coins
		want bool
	}{
		{"nil funds", nil, true},
		{"zero coin", chain.NewCoins(chain.NewCoin("ugnot", 0)), true},
		{"non-zero coin", chain.NewCoins(chain.NewCoin("ugnot", 1)), false},
		{"mixed zero and non-zero", chain.NewCoins(chain.NewCoin("ugnot", 0), chain.NewCoin("foo", 1)), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, newFunds(tc.have).isEmpty())
		})
	}
}

// assertEmpty must reject any leftover attached coin and accept a fully drained
// (or never-funded) budget.
func TestFundsAssertEmpty(t *testing.T) {
	empty := newFunds(nil)
	uassert.NoError(t, empty.assertEmpty())

	drained := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 10)))
	uassert.NoError(t, drained.sub("ugnot", u256.NewUint(10)))
	uassert.NoError(t, drained.assertEmpty())

	leftover := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 10)))
	uassert.NoError(t, leftover.sub("ugnot", u256.NewUint(4)))
	uassert.Error(t, leftover.assertEmpty())
}
