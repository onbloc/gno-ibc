package ucs03_zkgm

import (
	"errors"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

var errDummyVoucher = errors.New("dummy voucher error")

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

// TestVoucherApproveTransfer covers Voucher's self-service capability methods
// directly, at ledger precision (no origin-decimal scaling, unlike
// MintScaled/BurnScaled/TransferScaled): Approve sets an allowance without
// touching balances, and Transfer moves between two arbitrary holders.
func TestVoucherApproveTransfer(cur realm, t *testing.T) {
	token, ledger := newVoucherTokenForTest(cur, "Approve Transfer", "VAT")
	vou := NewVoucher(token, ledger, 0)

	holder := testutils.TestAddress("apprv-tx-holder")
	spender := testutils.TestAddress("apprv-tx-spender")
	receiver := testutils.TestAddress("apprv-tx-rx")

	uassert.NoError(t, ledger.Mint(holder, 100))

	uassert.NoError(t, vou.Approve(holder, spender, 40))
	uassert.Equal(t, int64(40), token.Allowance(holder, spender))
	uassert.Equal(t, int64(100), token.BalanceOf(holder)) // Approve never moves balance

	uassert.NoError(t, vou.Transfer(holder, receiver, 25))
	uassert.Equal(t, int64(75), token.BalanceOf(holder))
	uassert.Equal(t, int64(25), token.BalanceOf(receiver))

	uassert.Error(t, vou.Transfer(holder, receiver, 1000)) // insufficient balance
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

func TestVoucherApprove_RequiresInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "implementation not installed", func(cur realm) {
		VoucherApprove(cross(cur), "ibc/denom", address("g1spender"), 10)
	})
}

func TestVoucherApprove_DelegatesToInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	d := &dummyImpl{}
	installImplForTest(testImplPathA, d)
	spender := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	VoucherApprove(cross(cur), "ibc/approve-denom", spender, 42)

	uassert.True(t, d.voucherApproveCalled)
	uassert.Equal(t, "ibc/approve-denom", d.lastVoucherDenom)
	uassert.Equal(t, spender.String(), d.lastVoucherSpender.String())
	uassert.Equal(t, int64(42), d.lastVoucherAmount)
}

func TestVoucherApprove_RejectsPaused(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	d := &dummyImpl{}
	installImplForTest(testImplPathA, d)
	paused = true

	uassert.AbortsContains(t, cur, "paused", func(cur realm) {
		VoucherApprove(cross(cur), "ibc/approve-denom", address("g1spender"), 1)
	})
	uassert.False(t, d.voucherApproveCalled)
}

func TestVoucherApprove_PropagatesImplError(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	d := &dummyImpl{voucherErr: errDummyVoucher}
	installImplForTest(testImplPathA, d)

	uassert.AbortsContains(t, cur, errDummyVoucher.Error(), func(cur realm) {
		VoucherApprove(cross(cur), "ibc/approve-denom", address("g1spender"), 1)
	})
}

func TestVoucherTransfer_RequiresInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "implementation not installed", func(cur realm) {
		VoucherTransfer(cross(cur), "ibc/denom", address("g1receiver"), 10)
	})
}

func TestVoucherTransfer_DelegatesToInstalledImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	d := &dummyImpl{}
	installImplForTest(testImplPathA, d)
	to := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	VoucherTransfer(cross(cur), "ibc/transfer-denom", to, 7)

	uassert.True(t, d.voucherTransferCalled)
	uassert.Equal(t, "ibc/transfer-denom", d.lastVoucherDenom)
	uassert.Equal(t, to.String(), d.lastVoucherTo.String())
	uassert.Equal(t, int64(7), d.lastVoucherAmount)
}

func TestVoucherTransfer_RejectsPaused(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	d := &dummyImpl{}
	installImplForTest(testImplPathA, d)
	paused = true

	uassert.AbortsContains(t, cur, "paused", func(cur realm) {
		VoucherTransfer(cross(cur), "ibc/transfer-denom", address("g1receiver"), 1)
	})
	uassert.False(t, d.voucherTransferCalled)
}

func TestVoucherTransfer_PropagatesImplError(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	d := &dummyImpl{voucherErr: errDummyVoucher}
	installImplForTest(testImplPathA, d)

	uassert.AbortsContains(t, cur, errDummyVoucher.Error(), func(cur realm) {
		VoucherTransfer(cross(cur), "ibc/transfer-denom", address("g1receiver"), 1)
	})
}
