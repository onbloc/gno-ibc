package impl

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

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

// mintVoucher creates the wrapped token on first use, credits the receiver, and
// accumulates on repeat mints. An amount that overflows int64 must error.
func TestMintVoucher(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ibc/mint-basic"
	rx := address(testAddress("mint-rx"))

	uassert.NoError(t, v.mintVoucher(cur, denom, [32]byte{}, "Wrapped", "WRAP", 6, string(rx), u256.NewUint(100)))
	uassert.Equal(t, int64(100), voucherBalanceOf(denom, rx))
	uassert.Equal(t, 6, voucherDecimalsOf(denom))

	uassert.NoError(t, v.mintVoucher(cur, denom, [32]byte{}, "Wrapped", "WRAP", 6, string(rx), u256.NewUint(50)))
	uassert.Equal(t, int64(150), voucherBalanceOf(denom, rx))

	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
	uassert.Error(t, v.mintVoucher(cur, "ibc/mint-overflow", [32]byte{}, "X", "X", 0, string(rx), wide))
}

// burnVoucher / transferVoucher must reject an unknown denom up front, and an
// overflowing amount before touching the ledger.
func TestBurnAndTransferVoucher(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ibc/burn-basic"
	holder := address(testAddress("burn-holder"))
	other := address(testAddress("burn-other"))

	uassert.NoError(t, v.mintVoucher(cur, denom, [32]byte{}, "B", "B", 0, string(holder), u256.NewUint(100)))

	// burn reduces the holder's balance.
	uassert.NoError(t, v.burnVoucher(cur, denom, string(holder), u256.NewUint(40)))
	uassert.Equal(t, int64(60), voucherBalanceOf(denom, holder))

	// burning more than held is rejected by the ledger.
	uassert.Error(t, v.burnVoucher(cur, denom, string(holder), u256.NewUint(1000)))

	// transfer moves balance between holders (market-maker fill path).
	uassert.NoError(t, v.transferVoucher(cur, denom, holder, other, u256.NewUint(10)))
	uassert.Equal(t, int64(50), voucherBalanceOf(denom, holder))
	uassert.Equal(t, int64(10), voucherBalanceOf(denom, other))

	// unknown denom is rejected before any ledger access.
	uassert.Error(t, v.burnVoucher(cur, "ibc/missing", string(holder), u256.NewUint(1)))
	uassert.Error(t, v.transferVoucher(cur, "ibc/missing", holder, other, u256.NewUint(1)))
}

// getOrCreateVoucher falls back to the IBC denom for an empty name, and reuses
// the same token instance on subsequent lookups.
func TestVoucherNameFallsBackToIBCDenom(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ibc/name-fallback"
	rx := testAddress("name-fb-rx")

	uassert.NoError(t, v.mintVoucher(cur, denom, [32]byte{}, "", "SYM", 0, rx, u256.NewUint(1)))

	vou, ok := zkgm.Store().GetVoucher(denom)
	uassert.True(t, ok)
	uassert.Equal(t, denom, vou.Token().GetName())
}
