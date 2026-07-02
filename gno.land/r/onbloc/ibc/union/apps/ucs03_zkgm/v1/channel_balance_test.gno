package impl

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

// increaseChannelBalanceV2 accumulates deposits; a zero amount stores a zero entry.
// Each case uses a distinct base token so the shared store singleton keeps cases isolated.
func TestIncreaseChannelBalanceV2(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		deposits []uint64
		wantBal  uint64
		wantSet  bool
	}{
		{"single deposit", []uint64{500}, 500, true},
		{"accumulates deposits", []uint64{100, 250, 150}, 500, true},
		{"zero stores zero", []uint64{0}, 0, true},
		{"zero then real deposit", []uint64{0, 75}, 75, true},
	}
	v := newTestImpl()
	path := u256.Zero()
	quote := []byte("uosmo")
	for i, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			chanId := types.ChannelId(100 + i)
			base := []byte("inc-" + tc.name)
			for _, d := range tc.deposits {
				v.increaseChannelBalanceV2(0, cur, chanId, path, base, quote, u256.NewUint(d))
			}
			bal, ok := balanceOf(t, chanId, path, base, quote)
			uassert.Equal(t, tc.wantSet, ok)
			if tc.wantSet {
				uassert.Equal(t, tc.wantBal, bal)
			}
		})
	}
}

// increaseChannelBalanceV2 panics on uint256 overflow instead of silently
// wrapping the escrow balance back below its prior value. The balance is seeded
// directly in the store so a near-2^256 starting point is reachable, then a
// deposit that would cross the ceiling is rejected and the stored balance is left
// untouched.
func TestIncreaseChannelBalanceV2Overflow(cur realm, t *testing.T) {
	maxU256 := func() *u256.Uint { return new(u256.Uint).SetAllOne() }

	cases := []struct {
		name    string
		seed    *u256.Uint
		add     *u256.Uint
		wantErr bool
		wantBal *u256.Uint
	}{
		{"max plus one overflows", maxU256(), u256.NewUint(1), true, maxU256()},
		{"max plus large overflows", maxU256(), maxU256(), true, maxU256()},
		{"max plus zero stays max", maxU256(), u256.NewUint(0), false, maxU256()},
		{"sum to exactly max does not overflow", u256.Zero().Sub(maxU256(), u256.NewUint(5)), u256.NewUint(5), false, maxU256()},
	}
	v := newTestImpl()
	path := u256.Zero()
	quote := []byte("uosmo")
	for i, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			chanId := types.ChannelId(300 + i)
			base := []byte("incof-" + tc.name)
			key := ChannelBalanceKeyV2(chanId, path, base, quote)
			testStore.SetChannelBalanceV2(0, cur, key, tc.seed)

			if tc.wantErr {
				err := v.increaseChannelBalanceV2(0, cur, chanId, path, base, quote, tc.add)
				uassert.ErrorContains(t, err, errChannelBalanceOverflow)
			} else {
				err := v.increaseChannelBalanceV2(0, cur, chanId, path, base, quote, tc.add)
				uassert.NoError(t, err)
			}

			got, ok := testStore.GetChannelBalanceV2(key)
			uassert.True(t, ok)
			uassert.True(t, got.Eq(tc.wantBal))
		})
	}
}

// decreaseChannelBalanceV2 spends escrow: a partial spend leaves a remainder, an
// exact spend preserves a zero entry, an over-spend underflows, and a zero spend
// on an empty balance underflows.
func TestDecreaseChannelBalanceV2(cur realm, t *testing.T) {
	cases := []struct {
		name    string
		seed    uint64 // 0 => leave entry unset
		spend   uint64
		wantErr bool
		wantBal uint64
		wantSet bool
	}{
		{"partial leaves remainder", 500, 200, false, 300, true},
		{"exact spend preserves zero", 500, 500, false, 0, true},
		{"overspend underflows", 500, 501, true, 500, true},
		{"spend on empty underflows", 0, 1, true, 0, false},
		{"zero spend is noop", 500, 0, false, 500, true},
		{"zero spend on empty underflows", 0, 0, true, 0, false},
	}
	v := newTestImpl()
	path := u256.Zero()
	quote := []byte("uosmo")
	for i, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			chanId := types.ChannelId(200 + i)
			base := []byte("dec-" + tc.name)
			if tc.seed != 0 {
				v.increaseChannelBalanceV2(0, cur, chanId, path, base, quote, u256.NewUint(tc.seed))
			}
			err := v.decreaseChannelBalanceV2(0, cur, chanId, path, base, quote, u256.NewUint(tc.spend))
			if tc.wantErr {
				uassert.Error(t, err)
			} else {
				uassert.NoError(t, err)
			}
			bal, ok := balanceOf(t, chanId, path, base, quote)
			uassert.Equal(t, tc.wantSet, ok)
			if tc.wantSet {
				uassert.Equal(t, tc.wantBal, bal)
			}
		})
	}
}

// ChannelBalanceKeyV2 is a pure key derivation: identical inputs collide, and a
// change in any of the four components yields a distinct key.
func TestChannelBalanceKeyV2(t *testing.T) {
	chanId := types.ChannelId(1)
	path := u256.NewUint(42)
	base := []byte("uatom")
	quote := []byte("uosmo")
	ref := ChannelBalanceKeyV2(chanId, path, base, quote)

	uassert.Equal(t, ref, ChannelBalanceKeyV2(chanId, path, base, quote))

	cases := []struct {
		name string
		key  string
	}{
		{"different channel", ChannelBalanceKeyV2(types.ChannelId(2), path, base, quote)},
		{"different path", ChannelBalanceKeyV2(chanId, u256.NewUint(43), base, quote)},
		{"different base", ChannelBalanceKeyV2(chanId, path, []byte("uosmo"), quote)},
		{"different quote", ChannelBalanceKeyV2(chanId, path, base, []byte("uatom"))},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.NotEqual(t, ref, tc.key)
		})
	}
}

// balanceOf reads the current escrow balance, normalising a missing entry to 0.
func balanceOf(t *testing.T, chanId types.ChannelId, path *u256.Uint, base, quote []byte) (uint64, bool) {
	key := ChannelBalanceKeyV2(chanId, path, base, quote)
	bal, ok := testStore.GetChannelBalanceV2(key)
	if !ok || bal == nil {
		return 0, ok
	}
	return bal.Uint64(), ok
}
