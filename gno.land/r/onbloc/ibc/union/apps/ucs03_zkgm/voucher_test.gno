package ucs03_zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// TestVoucherScaling covers the origin->ledger encapsulation:
// an 18-dec origin wrapped by a 6-dec ledger downscales by 10^12
// through ToLedgerAmount, MintScaled and BurnScaled,
// and rejects sub-precision dust.
func TestVoucherScaling(cur realm, t *testing.T) {
	token, ledger := newVoucherTokenForTest(cur, "Scaled", "SCL")
	vou := NewVoucher(token, ledger, 18)

	uassert.Equal(t, uint8(18), vou.OriginDecimals())
	uassert.Equal(t, 12, vou.ScaleExp())

	oneToken := z.Pow10(18) // 1 whole 18-dec token, origin precision

	n, err := vou.ToLedgerAmount(oneToken)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(1000000), n) // downscaled to 1e6 ledger units

	_, err = vou.ToLedgerAmount(u256.Zero().Add(oneToken, u256.NewUint(1)))
	uassert.Error(t, err) // sub-precision dust fails closed

	holder := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	uassert.NoError(t, vou.MintScaled(holder, oneToken))
	uassert.Equal(t, int64(1000000), token.BalanceOf(holder))

	uassert.NoError(t, vou.BurnScaled(holder, oneToken))
	uassert.Equal(t, int64(0), token.BalanceOf(holder))
}

func TestNewVoucher(cur realm, t *testing.T) {
	token, ledger := newVoucherTokenForTest(cur, "Voucher Test", "VTST")
	vou := NewVoucher(token, ledger, 0)

	uassert.True(t, vou.Token() == token)
	uassert.True(t, vou.Ledger() == ledger)
}

func TestNewVoucher_RejectsSpoofedRealm(cur realm, t *testing.T) {
	// NewVoucher no longer takes a realm parameter, so spoofed realm
	// protection is handled at the store level (SetVoucher).
	// This test is kept for API surface coverage only.
	token, ledger := newVoucherTokenForTest(cur, "Spoofed Voucher", "VSPF")
	vou := NewVoucher(token, ledger, 0)

	uassert.True(t, vou.Token() == token)
	uassert.True(t, vou.Ledger() == ledger)
}

func TestVoucherAccessors(cur realm, t *testing.T) {
	token, ledger := newVoucherTokenForTest(cur, "Accessor Test", "VACC")
	vou := NewVoucher(token, ledger, 0)

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
	vou := NewVoucher(token, ledger, 0)

	uassert.Equal(t, int64(0), VoucherBalanceOf("ibc/missing-top-level-voucher", holder))

	store.SetVoucher(0, cur, denom, vou)
	err := ledger.Mint(holder, 33)
	if err != nil {
		t.Fatal(err)
	}

	uassert.Equal(t, int64(33), VoucherBalanceOf(denom, holder))
}
