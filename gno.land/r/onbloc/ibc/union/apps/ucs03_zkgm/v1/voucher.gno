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

// powersOf10[exp] = 10^exp for exp in 0..12 (max decimals 18 - target 6)
var powersOf10 = [13]*u256.Uint{
	u256.NewUint(1),             // 10^0
	u256.NewUint(10),            // 10^1
	u256.NewUint(100),           // 10^2
	u256.NewUint(1000),          // 10^3
	u256.NewUint(10000),         // 10^4
	u256.NewUint(100000),        // 10^5
	u256.NewUint(1000000),       // 10^6
	u256.NewUint(10000000),      // 10^7
	u256.NewUint(100000000),     // 10^8
	u256.NewUint(1000000000),    // 10^9
	u256.NewUint(10000000000),   // 10^10
	u256.NewUint(100000000000),  // 10^11
	u256.NewUint(1000000000000), // 10^12
}

// TokenInfo captures token metadata for decimal trimming in a single lookup.
type TokenInfo struct {
	decimals  uint8
	isVoucher bool
}

type TrimResult struct {
	Trimmed *u256.Uint
	Dust    *u256.Uint
}

func decimalFactor(tokenDecimals uint8) (*u256.Uint, error) {
	if tokenDecimals <= targetDecimals {
		return powersOf10[0], nil
	}

	exp := tokenDecimals - targetDecimals
	if int(exp) >= len(powersOf10) {
		return nil, makeError(errUnsupportedTokenDecimals)
	}

	return powersOf10[exp], nil
}

func trimAmount(tokenDecimals uint8, amount *u256.Uint) TrimResult {
	if tokenDecimals <= targetDecimals {
		return TrimResult{Trimmed: amount, Dust: u256.Zero()}
	}

	factor, err := decimalFactor(tokenDecimals)
	if err != nil {
		panic(err)
	}

	quotient := u256.Zero().Div(amount, factor)
	trimmed := u256.Zero().Mul(quotient, factor)
	dust := u256.Zero().Sub(amount, trimmed)

	return TrimResult{Trimmed: trimmed, Dust: dust}
}

func scaleLocalAmount(tokenDecimals uint8, amount *u256.Uint) (*u256.Uint, error) {
	factor, err := decimalFactor(tokenDecimals)
	if err != nil {
		return nil, err
	}

	if tokenDecimals <= targetDecimals {
		return amount, nil
	}

	return u256.Zero().Mul(amount, factor), nil
}

func wireAmountToLocal(tokenDecimals uint8, amount *u256.Uint) (*u256.Uint, error) {
	if tokenDecimals <= targetDecimals {
		return amount, nil
	}

	result := trimAmount(tokenDecimals, amount)
	if !result.Dust.IsZero() {
		return nil, makeError(errDecimalDust)
	}

	factor, err := decimalFactor(tokenDecimals)
	if err != nil {
		return nil, err
	}

	return u256.Zero().Div(amount, factor), nil
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

// parseTokenInfo extracts token metadata (decimals + voucher status) in a
// single lookup, combining the logic of the former shouldTrim/getTokenDecimals.
func (v *ucs03ZkgmV1) parseTokenInfo(_ int, rlm realm, denom []byte) TokenInfo {
	denomStr := string(denom)

	if vou, ok := v.store.GetVoucher(denomStr); ok {
		return TokenInfo{
			decimals:  uint8(vou.Token().GetDecimals()),
			isVoucher: true,
		}
	}

	return TokenInfo{decimals: targetDecimals, isVoucher: false}
}
