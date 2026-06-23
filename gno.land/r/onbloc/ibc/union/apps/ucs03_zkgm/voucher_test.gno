package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestNewVoucher(cur realm, t *testing.T) {
	token, ledger := newVoucherTokenForTest(cur, "Voucher Test", "VTST")
	vou := NewVoucher(0, cur, token, ledger)

	uassert.True(t, vou.Token() == token)
	uassert.True(t, vou.Ledger() == ledger)
}

func TestNewVoucherRejectsSpoofedRealm(cur realm, t *testing.T) {
	token, ledger := newVoucherTokenForTest(cur, "Spoofed Voucher", "VSPF")
	spoofedRealm := cur.Previous()

	cases := []struct {
		name      string
		rlm       realm
		wantAbort string
	}{
		{"current realm", cur, ""},
		{"spoofed realm", spoofedRealm, ErrSpoofedRealm},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					NewVoucher(0, tc.rlm, token, ledger)
				})
				return
			}

			vou := NewVoucher(0, tc.rlm, token, ledger)
			uassert.True(t, vou.Token() == token)
			uassert.True(t, vou.Ledger() == ledger)
		})
	}
}

func TestVoucherAccessors(cur realm, t *testing.T) {
	token, ledger := newVoucherTokenForTest(cur, "Accessor Test", "VACC")
	vou := NewVoucher(0, cur, token, ledger)

	cases := []struct {
		name       string
		wantToken  bool
		wantLedger bool
	}{
		{"token accessor", true, false},
		{"ledger accessor", false, true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.wantToken {
				uassert.True(t, vou.Token() == token)
			}
			if tc.wantLedger {
				uassert.True(t, vou.Ledger() == ledger)
			}
		})
	}
}

func TestVoucherBalanceOf(cur realm, t *testing.T) {
	const denom = "ibc/top-level-voucher-balance"
	holder := address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	token, ledger := newVoucherTokenForTest(cur, "Balance Test", "VBAL")
	vou := NewVoucher(0, cur, token, ledger)

	uassert.Equal(t, int64(0), VoucherBalanceOf("ibc/missing-top-level-voucher", holder))

	store.SetVoucher(0, cur, denom, vou)
	err := ledger.Mint(holder, 33)
	if err != nil {
		t.Fatal(err)
	}

	uassert.Equal(t, int64(33), VoucherBalanceOf(denom, holder))
}
