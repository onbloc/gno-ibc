package impl

import (
	"errors"
	"math"
	"strings"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
)

type voucher struct {
	token  *grc20.Token
	ledger *grc20.PrivateLedger
}

var voucherTokens = bptree.NewBPTree32()

func getOrCreateVoucherV2(cur realm, ibcDenom string, baseDenom string, metadataImage [32]byte, name, symbol string, decimals int) *voucher {
	if v, ok := voucherTokens.Get(ibcDenom); ok {
		return v.(*voucher)
	}

	// Fall back to ibcDenom-derived values if the caller did not supply metadata.
	// GRC20 symbols are restricted to [A-Za-z0-9_-]+ with a maximum length of
	// 11 characters, so sanitize whatever the source chain sent before use.
	if name == "" {
		name = ibcDenom
	}
	symbol = sanitizeGRC20Symbol(symbol, ibcDenom)

	token, ledger := grc20.NewToken(0, cur, name, symbol, decimals)
	grc20reg.Register(cross(cur), token, strings.TrimPrefix(ibcDenom, ibcDenomPrefix))

	v := &voucher{token: token, ledger: ledger}
	voucherTokens.Set(ibcDenom, v)

	zkgm.SetMetadataImageOf(cross(cur), ibcDenom, metadataImage)
	return v
}

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

func getVoucher(ibcDenom string) *voucher {
	v, ok := voucherTokens.Get(ibcDenom)
	if !ok {
		return nil
	}
	return v.(*voucher)
}

func mintVoucher(cur realm, ibcDenom string, baseDenom string, metadataImage [32]byte, name, symbol string, decimals int, receiver string, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}

	v := getOrCreateVoucherV2(cur, ibcDenom, baseDenom, metadataImage, name, symbol, decimals)
	return v.ledger.Mint(address(receiver), n)
}

func burnVoucher(cur realm, ibcDenom string, sender string, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}
	v := getVoucher(ibcDenom)
	if v == nil {
		return errors.New("zkgm/voucher: not found: " + ibcDenom)
	}
	return v.ledger.Burn(address(sender), n)
}

// VoucherBalanceOf returns the addr's balance of the voucher token for ibcDenom,
// or 0 if no voucher exists for that denom.
func VoucherBalanceOf(ibcDenom string, addr address) int64 {
	v := getVoucher(ibcDenom)
	if v == nil {
		return 0
	}
	return v.token.BalanceOf(addr)
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
