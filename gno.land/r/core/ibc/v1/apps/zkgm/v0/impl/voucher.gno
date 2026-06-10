package impl

import (
	"errors"
	"math"
	"strings"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
)

// sanitizeGRC20Symbol returns a GRC20-valid symbol derived from the supplied
// candidate. Characters outside [A-Za-z0-9_-] are stripped, the result is
// truncated to MaxSymbolLen, and if nothing valid remains the ibcDenom hex
// suffix is used as a safe fallback.
func sanitizeGRC20Symbol(candidate, ibcDenom string) string {
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

func mintVoucher(cur realm, ibcDenom string, baseDenom string, metadataImage [32]byte, name, symbol string, decimals uint8, receiver string, amount *u256.Uint) error {
	return zkgm.MintVoucher(cross(cur), ibcDenom, baseDenom, metadataImage, name, sanitizeGRC20Symbol(symbol, ibcDenom), decimals, receiver, amount)
}

func burnVoucher(cur realm, ibcDenom string, sender string, amount *u256.Uint) error {
	return zkgm.BurnVoucher(cross(cur), ibcDenom, sender, amount)
}

// VoucherBalanceOf returns the addr's balance of the voucher token for ibcDenom,
// or 0 if no voucher exists for that denom.
func VoucherBalanceOf(ibcDenom string, addr address) int64 {
	return zkgm.VoucherBalanceOf(ibcDenom, addr)
}

func VoucherDecimalsOf(ibcDenom string) int {
	return zkgm.VoucherDecimalsOf(ibcDenom)
}

var errAmountOverflow = errors.New("zkgm/voucher: amount overflows int64")

// amountInt64 narrows a uint256 amount to int64 for banker/grc20 APIs.
// Returns an error so a malicious oversized amount surfaces as a packet
// failure ack rather than panicking and wedging the channel.
func amountInt64(amount *u256.Uint) (int64, error) {
	if !amount.IsUint64() || amount.Uint64() > uint64(math.MaxInt64) {
		return 0, errAmountOverflow
	}
	return amount.Int64(), nil
}
