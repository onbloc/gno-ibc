package ucs03_zkgm

import (
	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// Voucher bundles a wrapped grc20 token, its private mint/burn ledger,
// and the origin token's decimal precision.
// It is proxy-owned state held in the Store,
// so its mint/burn rights survive impl upgrades.
//
// Packet amounts are in the origin token's decimals;
// the grc20 ledger holds them downscaled to the (possibly capped) ledger decimals,
// so they fit int64.
// MintScaled / BurnScaled / TransferScaled apply that downscale,
// so callers never combine the scale and the ledger by hand;
// the raw int64 ops stay reachable via Ledger().
//
// SECURITY: those methods and Ledger() all hand out the mint/burn capability,
// so a *Voucher must stay impl-gated.
// The Store is injected and never publicly returned,
// so untrusted realms can only read balances via VoucherBalanceOf.
type Voucher struct {
	token          *grc20.Token
	ledger         *grc20.PrivateLedger
	originDecimals uint8
}

// NewVoucher is a crossing-safe constructor,
// so the impl realm can build one without tripping the foreign-composite-literal rule.
// originDecimals is the origin token's precision;
// the ledger token is created at min(originDecimals, ledger cap).
func NewVoucher(token *grc20.Token, ledger *grc20.PrivateLedger, originDecimals uint8) *Voucher {
	return &Voucher{token: token, ledger: ledger, originDecimals: originDecimals}
}

// Token returns the read-only token handle (safe: balances, metadata).
func (v *Voucher) Token() *grc20.Token { return v.token }

// Ledger returns the mint/burn capability. Callers MUST be impl-gated.
func (v *Voucher) Ledger() *grc20.PrivateLedger { return v.ledger }

// OriginDecimals returns the origin token's precision.
// The scalar is copied across the realm boundary, so impl reads are safe.
func (v *Voucher) OriginDecimals() uint8 { return v.originDecimals }

// ScaleExp is the origin->ledger downscale exponent:
// the low-order digits dropped between origin precision and the ledger token's precision.
// Derived from both stored decimals, so it needs no global constant,
// and clamps to 0 for native/low-decimal tokens.
func (v *Voucher) ScaleExp() int {
	exp := int(v.originDecimals) - v.token.GetDecimals()
	if exp < 0 {
		return 0
	}

	return exp
}

// ToLedgerAmount narrows an origin-precision amount to this voucher's int64 ledger amount,
// rejecting sub-precision dust and int64 overflow.
// MintScaled, BurnScaled, TransferScaled and the impl's pre-flight checks all route through it.
func (v *Voucher) ToLedgerAmount(amount *u256.Uint) (int64, error) {
	return z.ScaleDownToInt64(amount, v.ScaleExp())
}

// MintScaled credits an origin-precision amount, downscaled to the ledger.
// Carries the mint capability; callers MUST be impl-gated.
func (v *Voucher) MintScaled(receiver address, amount *u256.Uint) error {
	n, err := v.ToLedgerAmount(amount)
	if err != nil {
		return err
	}

	return v.ledger.Mint(receiver, n)
}

// BurnScaled debits an origin-precision amount, downscaled to the ledger.
// Carries the burn capability; callers MUST be impl-gated.
func (v *Voucher) BurnScaled(holder address, amount *u256.Uint) error {
	n, err := v.ToLedgerAmount(amount)
	if err != nil {
		return err
	}

	return v.ledger.Burn(holder, n)
}

// TransferScaled moves an origin-precision amount between holders, downscaled to the ledger.
// Carries the ledger capability; callers MUST be impl-gated.
func (v *Voucher) TransferScaled(from, to address, amount *u256.Uint) error {
	n, err := v.ToLedgerAmount(amount)
	if err != nil {
		return err
	}

	return v.ledger.Transfer(from, to, n)
}

// VoucherBalanceOf returns addr's wrapped-voucher balance for ibcDenom, or 0 if none.
// It reads the proxy-owned Store,
// so the balance survives impl upgrades and does not depend on grc20reg's key.
func VoucherBalanceOf(ibcDenom string, addr address) int64 {
	vou, ok := store.GetVoucher(ibcDenom)
	if !ok {
		return 0
	}

	return vou.Token().BalanceOf(addr)
}
