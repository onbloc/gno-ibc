package v1

import (
	"chain"
	"chain/banker"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestSendNative(cur realm, t *testing.T) {
	v := newTestImpl()
	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64) // > int64, > uint64
	bk := banker.NewReadonlyBanker()

	cases := []struct {
		name         string
		denom        string
		receiver     address
		seedEscrow   int64
		amount       *u256.Uint
		wantErr      bool
		wantEscrow   int64
		wantReceiver int64
	}{
		{
			name:         "happy path sends native coins from escrow",
			denom:        "usendhappy",
			receiver:     address(testAddress("escrow-happy")),
			seedEscrow:   50,
			amount:       u256.NewUint(30),
			wantEscrow:   20,
			wantReceiver: 30,
		},
		{
			name:         "exact balance send drains escrow",
			denom:        "usendexact",
			receiver:     address(testAddress("escrow-exact")),
			seedEscrow:   40,
			amount:       u256.NewUint(40),
			wantEscrow:   0,
			wantReceiver: 40,
		},
		{
			name:       "overflow amount returns error before banker send",
			denom:      "usendoverflow",
			receiver:   address(testAddress("escrow-overflow")),
			seedEscrow: 100,
			amount:     wide,
			wantErr:    true,
			wantEscrow: 100,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.seedEscrow > 0 {
				testing.IssueCoins(cur.Address(), chain.NewCoins(chain.NewCoin(tc.denom, tc.seedEscrow)))
			}

			err := v.sendNative(0, cur, tc.denom, tc.receiver, tc.amount)
			if tc.wantErr {
				uassert.Error(t, err)
			} else {
				uassert.NoError(t, err)
			}

			uassert.Equal(t, tc.wantEscrow, bk.GetCoins(cur.Address()).AmountOf(tc.denom))
			uassert.Equal(t, tc.wantReceiver, bk.GetCoins(tc.receiver).AmountOf(tc.denom))
		})
	}
}
