package ucs03_zkgm

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

// VoucherApproveX/VoucherTransferX are crossing test shims: the production
// methods read the holder from rlm.Previous().Address(), which a direct
// non-crossing call leaves empty. Driving them via testing.SetRealm(
// testing.NewUserRealm(holder)) + cross(cur) reproduces the proxy's real call
// shape (see call_union_test.gno for the same pattern).
func (v *ucs03ZkgmV1) VoucherApproveX(cur realm, ibcDenom string, spender address, amount int64) error {
	return v.VoucherApprove(0, cur, ibcDenom, spender, amount)
}

func (v *ucs03ZkgmV1) VoucherTransferX(cur realm, ibcDenom string, to address, amount int64) error {
	return v.VoucherTransfer(0, cur, ibcDenom, to, amount)
}

// amountInt64 narrows uint256 to int64 for the banker/grc20 APIs; anything above
// MaxInt64 must surface as an error rather than a silent wrap or panic.
func TestAmountInt64(t *testing.T) {
	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
	cases := []struct {
		name    string
		input   *u256.Uint
		want    int64
		wantErr bool
	}{
		{"zero", u256.NewUint(0), 0, false},
		{"one", u256.NewUint(1), 1, false},
		{"max int64 - 1", u256.NewUint(uint64(math.MaxInt64) - 1), math.MaxInt64 - 1, false},
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
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, got)
		})
	}
}

// sanitizeVoucherSymbol must yield a grc20-legal symbol: it strips disallowed
// characters, caps the length at MaxSymbolLen, and falls back to the IBC hash
// (prefix-trimmed) when nothing legal remains.
func TestSanitizeVoucherSymbol(t *testing.T) {
	cases := []struct {
		name      string
		candidate string
		ibcDenom  string
		want      string
	}{
		{"legal symbol kept", "USDC", "ibc/abc", "USDC"},
		{"strips illegal chars", "U$D C!", "ibc/abc", "UDC"},
		{"keeps underscore and dash", "a_b-c", "ibc/abc", "a_b-c"},
		{"truncates to max len", "ABCDEFGHIJKLMNOP", "ibc/abc", "ABCDEFGHIJK"},
		{"empty falls back to trimmed denom", "", "ibc/deadbeef", "deadbeef"},
		{"all-illegal falls back to trimmed denom", "###", "ibc/cafe", "cafe"},
		{"fallback truncated to max len", "", "ibc/0123456789abcdef", "0123456789a"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, sanitizeVoucherSymbol(tc.candidate, tc.ibcDenom))
		})
	}
}

func TestGetOrCreateVoucher(cur realm, t *testing.T) {
	cases := []struct {
		name       string
		denom      string
		nameArg    string
		symbolArg  string
		decimals   uint8
		precreate  bool
		wantName   string
		wantSymbol string
		wantDec    int
	}{
		{"creates voucher", "ibc/direct-create", "Wrapped", "WRAP", 6, false, "Wrapped", "WRAP", 6},
		{"empty name falls back to denom", "ibc/direct-name-fallback", "", "SYM", 3, false, "ibc/direct-name-fallback", "SYM", 3},
		{"sanitizes symbol", "ibc/direct-symbol", "Name", "$B A D!", 2, false, "Name", "BAD", 2},
		{"reuses existing voucher", "ibc/direct-reuse", "Ignored", "IGN", 9, true, "Original", "ORG", 4},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			v := newTestImpl()
			if tc.precreate {
				_, err := v.getOrCreateVoucher(0, cur, tc.denom, [32]byte{}, "Original", "ORG", 4)
				uassert.NoError(t, err)
			}

			got, err := v.getOrCreateVoucher(0, cur, tc.denom, [32]byte{}, tc.nameArg, tc.symbolArg, tc.decimals)
			uassert.NoError(t, err)
			stored, ok := testStore.GetVoucher(tc.denom)
			uassert.True(t, ok)
			uassert.True(t, got == stored)
			uassert.Equal(t, tc.wantName, got.Token().GetName())
			uassert.Equal(t, tc.wantSymbol, got.Token().GetSymbol())
			uassert.Equal(t, tc.wantDec, got.Token().GetDecimals())
		})
	}
}

// grc20reg keys its registry by (realm, symbol) and panics on a repeat key.
// Every voucher this realm registers shares the same realm path, so two
// different origin denoms that happen to declare the same symbol (e.g. USDC
// bridged from two different chains) must fail with a controlled error
// instead of panicking through grc20reg.Register.
func TestGetOrCreateVoucherRejectsDuplicateSymbolAcrossDenoms(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	_, err := v.getOrCreateVoucher(0, cur, "ibc/origin-chain-a-usdc", [32]byte{}, "USD Coin", "USDC", 6)
	uassert.NoError(t, err)

	_, err = v.getOrCreateVoucher(0, cur, "ibc/origin-chain-b-usdc", [32]byte{}, "USD Coin", "USDC", 6)
	uassert.ErrorContains(t, err, "voucher symbol already registered")

	// The first denom's voucher is unaffected, and the second was never created.
	_, ok := testStore.GetVoucher("ibc/origin-chain-a-usdc")
	uassert.True(t, ok)
	_, ok = testStore.GetVoucher("ibc/origin-chain-b-usdc")
	uassert.False(t, ok)
}

// Voucher operations create and reuse wrapped grc20 tokens while preserving
// ledger error behavior for mint, burn, and transfer paths.
func TestVoucher(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(t *testing.T, rlm realm, v *ucs03ZkgmV1)
	}{
		{
			name: "mint creates voucher accumulates balance and rejects overflow",
			run: func(t *testing.T, rlm realm, v *ucs03ZkgmV1) {
				denom := "ibc/mint-basic"
				rx := address(testAddress("mint-rx"))

				uassert.NoError(t, v.mintVoucher(0, rlm, denom, [32]byte{}, "Wrapped", "MINTVB", 6, rx, u256.NewUint(100)))
				uassert.Equal(t, int64(100), voucherBalanceOf(denom, rx))
				uassert.Equal(t, 6, voucherDecimalsOf(denom))

				uassert.NoError(t, v.mintVoucher(0, rlm, denom, [32]byte{}, "Wrapped", "MINTVB", 6, rx, u256.NewUint(50)))
				uassert.Equal(t, int64(150), voucherBalanceOf(denom, rx))

				wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
				uassert.Error(t, v.mintVoucher(0, rlm, "ibc/mint-overflow", [32]byte{}, "X", "X", 0, rx, wide))
			},
		},
		{
			name: "burn reduces balance and rejects insufficient or unknown voucher",
			run: func(t *testing.T, rlm realm, v *ucs03ZkgmV1) {
				denom := "ibc/burn-basic"
				holder := address(testAddress("burn-holder"))

				uassert.NoError(t, v.mintVoucher(0, rlm, denom, [32]byte{}, "B", "B", 0, holder, u256.NewUint(100)))
				uassert.NoError(t, v.burnVoucher(0, rlm, denom, holder, u256.NewUint(40)))
				uassert.Equal(t, int64(60), voucherBalanceOf(denom, holder))

				uassert.Error(t, v.burnVoucher(0, rlm, denom, holder, u256.NewUint(1000)))
				uassert.Error(t, v.burnVoucher(0, rlm, "ibc/missing", holder, u256.NewUint(1)))
			},
		},
		{
			name: "transfer moves balance and rejects unknown voucher",
			run: func(t *testing.T, rlm realm, v *ucs03ZkgmV1) {
				denom := "ibc/transfer-basic"
				holder := address(testAddress("transfer-holder"))
				other := address(testAddress("transfer-other"))

				uassert.NoError(t, v.mintVoucher(0, rlm, denom, [32]byte{}, "T", "T", 0, holder, u256.NewUint(100)))
				uassert.NoError(t, v.transferVoucher(0, rlm, denom, holder, other, u256.NewUint(10)))
				uassert.Equal(t, int64(90), voucherBalanceOf(denom, holder))
				uassert.Equal(t, int64(10), voucherBalanceOf(denom, other))

				uassert.Error(t, v.transferVoucher(0, rlm, "ibc/missing", holder, other, u256.NewUint(1)))
			},
		},
		{
			name: "empty name falls back to ibc denom",
			run: func(t *testing.T, rlm realm, v *ucs03ZkgmV1) {
				denom := "ibc/name-fallback"
				rx := testAddress("name-fb-rx")

				uassert.NoError(t, v.mintVoucher(0, rlm, denom, [32]byte{}, "", "EMPTYNM", 0, rx, u256.NewUint(1)))

				vou, ok := testStore.GetVoucher(denom)
				uassert.True(t, ok)
				uassert.Equal(t, denom, vou.Token().GetName())
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			tc.run(t, cur, newTestImpl())
		})
	}
}

// VoucherApprove/VoucherTransfer let a voucher holder self-service their own
// balance without exposing mintVoucher/burnVoucher's supply capability.
func TestVoucherApprove(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	denom := "ibc/approve-basic"
	holder := testAddress("approve-holder")
	spender := testAddress("approve-spender")

	uassert.NoError(t, v.mintVoucher(0, cur, denom, [32]byte{}, "A", "A", 0, holder, u256.NewUint(100)))

	testing.SetRealm(testing.NewUserRealm(holder))
	uassert.NoError(t, v.VoucherApproveX(cross(cur), denom, spender, 40))

	vou, ok := testStore.GetVoucher(denom)
	uassert.True(t, ok)
	uassert.Equal(t, int64(40), vou.Token().Allowance(holder, spender))

	// Approve carries no mint/burn capability: the holder's own balance is untouched.
	uassert.Equal(t, int64(100), voucherBalanceOf(denom, holder))
}

func TestVoucherApprove_UnknownVoucher(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	holder := testAddress("approve-miss-holder")
	testing.SetRealm(testing.NewUserRealm(holder))

	uassert.ErrorContains(t, v.VoucherApproveX(cross(cur), "ibc/missing-approve", testAddress("approve-miss-spender"), 1), "voucher not found")
}

func TestVoucherTransfer(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	denom := "ibc/transfer-self-service"
	holder := testAddress("transfer-self-holder")
	other := testAddress("transfer-self-other")
	receiver := testAddress("transfer-self-rx")

	uassert.NoError(t, v.mintVoucher(0, cur, denom, [32]byte{}, "TSELF", "TSELF", 0, holder, u256.NewUint(100)))
	uassert.NoError(t, v.mintVoucher(0, cur, denom, [32]byte{}, "TSELF", "TSELF", 0, other, u256.NewUint(100)))

	testing.SetRealm(testing.NewUserRealm(holder))
	uassert.NoError(t, v.VoucherTransferX(cross(cur), denom, receiver, 25))

	uassert.Equal(t, int64(75), voucherBalanceOf(denom, holder))
	uassert.Equal(t, int64(25), voucherBalanceOf(denom, receiver))
	// Only the calling holder's balance moves; other holders are untouched.
	uassert.Equal(t, int64(100), voucherBalanceOf(denom, other))
}

func TestVoucherTransfer_UnknownVoucher(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	holder := testAddress("transfer-miss-holder")
	testing.SetRealm(testing.NewUserRealm(holder))

	uassert.ErrorContains(t, v.VoucherTransferX(cross(cur), "ibc/missing-transfer", testAddress("transfer-miss-rx"), 1), "voucher not found")
}
