package impl

import (
	"errors"
	"math"
	"strings"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

type voucher struct {
	token  *grc20.Token
	ledger *grc20.PrivateLedger
}

var voucherTokens = bptree.NewBPTree32()

func getOrCreateVoucherV2(cur realm, ibcDenom string, baseDenom string, metadataImage [32]byte) *voucher {
	if v, ok := voucherTokens.Get(ibcDenom); ok {
		return v.(*voucher)
	}

	token, ledger := grc20.NewToken(baseDenom, ibcDenom, 0)
	grc20reg.Register(cross, token, strings.TrimPrefix(ibcDenom, ibcDenomPrefix))

	v := &voucher{token: token, ledger: ledger}
	voucherTokens.Set(ibcDenom, v)

	zkgm.SetMetadataImageOf(cross, ibcDenom, metadataImage)
	return v
}

func getVoucher(ibcDenom string) *voucher {
	v, ok := voucherTokens.Get(ibcDenom)
	if !ok {
		return nil
	}
	return v.(*voucher)
}

func mintVoucher(cur realm, ibcDenom string, baseDenom string, metadataImage [32]byte, receiver string, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}

	v := getOrCreateVoucherV2(cur, ibcDenom, baseDenom, metadataImage)
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
