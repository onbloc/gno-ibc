package impl

import (
	"math"
	"strings"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

const (
	targetDecimals = 6
)

// TokenInfo captures known local voucher metadata in a single lookup.
type TokenInfo struct {
	decimals  uint8
	isVoucher bool
}

func decimalFactor(tokenDecimals uint8) (*u256.Uint, error) {
	if tokenDecimals <= targetDecimals {
		return u256.NewUint(1), nil
	}

	exp := tokenDecimals - targetDecimals
	if exp > 12 {
		return nil, makeError(errUnsupportedTokenDecimals)
	}

	factor := u256.NewUint(1)
	for i := uint8(0); i < exp; i++ {
		factor.Mul(factor, u256.NewUint(10))
	}

	return factor, nil
}

func scaleLocalAmount(tokenDecimals uint8, amount *u256.Uint) (*u256.Uint, error) {
	factor, err := decimalFactor(tokenDecimals)
	if err != nil {
		return nil, err
	}

	if tokenDecimals <= targetDecimals {
		return amount.Clone(), nil
	}

	scaled, overflow := u256.Zero().MulOverflow(amount, factor)
	if overflow {
		return nil, makeError(errAmountOverflow)
	}

	return scaled, nil
}

func wireAmountToLocal(tokenDecimals uint8, amount *u256.Uint) (*u256.Uint, error) {
	if tokenDecimals <= targetDecimals {
		return amount.Clone(), nil
	}

	factor, err := decimalFactor(tokenDecimals)
	if err != nil {
		return nil, err
	}

	quotient := u256.Zero().Div(amount, factor)
	if !u256.Zero().Sub(amount, u256.Zero().Mul(quotient, factor)).IsZero() {
		return nil, makeError(errDecimalDust)
	}

	return quotient, nil
}

// mintVoucher mints `amount` of the wrapped grc20 voucher for ibcDenom to
// receiver, creating the voucher token on first use. The grc20 ledger capability
// lives in the proxy-owned store, so mint/burn rights survive impl upgrades.
func (v *ucs03ZkgmV1) mintVoucher(_ int, rlm realm, ibcDenom string, image [32]byte, name, symbol string, decimals uint8, receiver string, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}

	vou := v.getOrCreateVoucher(0, rlm, ibcDenom, image, name, symbol, decimals)

	return vou.Ledger().Mint(address(receiver), n)
}

// burnVoucher burns amount of the wrapped voucher held by sender.
func (v *ucs03ZkgmV1) burnVoucher(_ int, rlm realm, ibcDenom, sender string, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}

	vou, ok := v.store.GetVoucher(ibcDenom)
	if !ok {
		return makeError(errVoucherNotFound, ibcDenom)
	}

	return vou.Ledger().Burn(address(sender), n)
}

// transferVoucher moves amount of the wrapped voucher between holders (market-maker fill).
func (v *ucs03ZkgmV1) transferVoucher(_ int, rlm realm, ibcDenom string, from, to address, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}

	vou, ok := v.store.GetVoucher(ibcDenom)
	if !ok {
		return makeError(errVoucherNotFound, ibcDenom)
	}

	return vou.Ledger().Transfer(from, to, n)
}

// getOrCreateVoucher returns the wrapped grc20 voucher for ibcDenom, creating and registering it on first use.
func (v *ucs03ZkgmV1) getOrCreateVoucher(_ int, rlm realm, ibcDenom string, image [32]byte, name, symbol string, decimals uint8) *zkgm.Voucher {
	if vou, ok := v.store.GetVoucher(ibcDenom); ok {
		return vou
	}

	if name == "" {
		name = ibcDenom
	}

	symbol = sanitizeVoucherSymbol(symbol, ibcDenom)

	token, ledger := grc20.NewToken(0, rlm, name, symbol, int(decimals))
	grc20reg.Register(cross(rlm), token, strings.TrimPrefix(ibcDenom, ibcDenomPrefix))

	voucher := zkgm.NewVoucher(token, ledger)
	v.store.SetVoucher(0, rlm, ibcDenom, voucher)

	return voucher
}

// sanitizeVoucherSymbol derives a grc20-legal symbol (<=MaxSymbolLen, [A-Za-z0-9_-])
// from the candidate, falling back to a prefix of the IBC hash when empty.
func sanitizeVoucherSymbol(candidate, ibcDenom string) string {
	out := make([]byte, 0, grc20.MaxSymbolLen)
	for i := 0; i < len(candidate) && len(out) < grc20.MaxSymbolLen; i++ {
		c := candidate[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' {
			out = append(out, c)
		}
	}

	if len(out) == 0 {
		fallback := strings.TrimPrefix(ibcDenom, ibcDenomPrefix)
		if len(fallback) > grc20.MaxSymbolLen {
			fallback = fallback[:grc20.MaxSymbolLen]
		}

		return fallback
	}

	return string(out)
}

// amountInt64 narrows a uint256 amount to int64 for banker/grc20 APIs, returning
// an error so an oversized amount surfaces as a failure ack rather than a panic.
func amountInt64(amount *u256.Uint) (int64, error) {
	if !amount.IsUint64() || amount.Uint64() > uint64(math.MaxInt64) {
		return 0, makeError(errAmountOverflow)
	}

	return amount.Int64(), nil
}

// parseTokenInfo extracts local voucher metadata in a single lookup.
func (v *ucs03ZkgmV1) parseTokenInfo(_ int, rlm realm, denom []byte) TokenInfo {
	denomStr := string(denom)

	if vou, ok := v.store.GetVoucher(denomStr); ok {
		decimals, ok := v.store.GetTokenDecimals(denomStr)
		if !ok {
			decimals = uint8(vou.Token().GetDecimals())
		}

		return TokenInfo{
			decimals:  decimals,
			isVoucher: true,
		}
	}

	return TokenInfo{isVoucher: false}
}
