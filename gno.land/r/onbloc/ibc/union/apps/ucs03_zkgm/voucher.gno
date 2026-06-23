package zkgm

import "gno.land/p/demo/tokens/grc20"

// Voucher bundles a wrapped grc20 token with its private mint/burn ledger. It is
// proxy-owned *state* held in the Store; all voucher *logic* (mint/burn/transfer,
// getOrCreate, decimal scaling) lives in the impl realm.
//
// The Store holds the ledger capability so that mint/burn rights survive impl
// upgrades: v2 receives the same injected Store and keeps operating the same
// token.
//
// SECURITY: Ledger() hands out the mint/burn capability. The impl-facing access
// to vouchers must be gated (the impl boundary), never exposed as an open public
// getter, or any realm could mint. See VOUCHER_ANALYSIS.md.
type Voucher struct {
	token  *grc20.Token
	ledger *grc20.PrivateLedger
}

// NewVoucher builds a Voucher value. Provided as a crossing-safe constructor so
// the impl realm can assemble one (v2 borrow rule #1 forbids constructing a
// foreign-stamped composite literal directly).
func NewVoucher(_ int, rlm realm, token *grc20.Token, ledger *grc20.PrivateLedger) *Voucher {
	return &Voucher{token: token, ledger: ledger}
}

// Token returns the read-only token handle (safe: balances, metadata).
func (v *Voucher) Token() *grc20.Token { return v.token }

// Ledger returns the mint/burn capability. Callers MUST be impl-gated.
func (v *Voucher) Ledger() *grc20.PrivateLedger { return v.ledger }

// VoucherBalanceOf returns addr's balance of the wrapped voucher for ibcDenom,
// or 0 when no voucher has been minted for it. It reads the proxy-owned Store, so
// the balance is the stable public surface: it survives impl upgrades and does
// not depend on grc20reg's realm-qualified registration key.
func VoucherBalanceOf(ibcDenom string, addr address) int64 {
	vou, ok := store.GetVoucher(ibcDenom)
	if !ok {
		return 0
	}

	return vou.Token().BalanceOf(addr)
}
