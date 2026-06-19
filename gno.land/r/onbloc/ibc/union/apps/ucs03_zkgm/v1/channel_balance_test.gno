package impl

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

// balanceOf reads the current escrow balance, normalising a missing entry to 0.
func balanceOf(chanId types.ChannelId, path *u256.Uint, base, quote []byte) (uint64, bool) {
	key := ChannelBalanceKeyV2(chanId, path, base, quote)
	bal, ok := testStore.GetChannelBalanceV2(key)
	if !ok || bal == nil {
		return 0, ok
	}
	return bal.Uint64(), ok
}

// increaseChannelBalanceV2 accumulates deposits; a zero amount must not create
// an entry. Each case uses a distinct base token so the shared store singleton
// keeps cases isolated.
func TestIncreaseChannelBalanceV2(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		deposits []uint64
		wantBal  uint64
		wantSet  bool
	}{
		{"single deposit", []uint64{500}, 500, true},
		{"accumulates deposits", []uint64{100, 250, 150}, 500, true},
		{"zero is noop", []uint64{0}, 0, false},
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
			bal, ok := balanceOf(chanId, path, base, quote)
			uassert.Equal(t, tc.wantSet, ok)
			if tc.wantSet {
				uassert.Equal(t, tc.wantBal, bal)
			}
		})
	}
}

// decreaseChannelBalanceV2 spends escrow: a partial spend leaves a remainder, an
// exact spend clears the entry, an over-spend underflows, and a zero spend is a
// noop that never touches the entry.
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
		{"exact spend clears entry", 500, 500, false, 0, false},
		{"overspend underflows", 500, 501, true, 500, true},
		{"spend on empty underflows", 0, 1, true, 0, false},
		{"zero spend is noop", 500, 0, false, 500, true},
		{"zero spend on empty stays empty", 0, 0, false, 0, false},
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
			bal, ok := balanceOf(chanId, path, base, quote)
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
