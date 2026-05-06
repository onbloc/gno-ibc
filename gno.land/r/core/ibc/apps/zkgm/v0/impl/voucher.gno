package impl

import (
	"errors"
	"math"
	"strings"

	"gno.land/p/nt/bptree/v0"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/r/demo/defi/grc20reg"

	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
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
	v := getOrCreateVoucherV2(cur, ibcDenom, baseDenom, metadataImage)
	return v.ledger.Mint(address(receiver), amountInt64(amount))
}

func burnVoucher(cur realm, ibcDenom string, sender string, amount *u256.Uint) error {
	v := getVoucher(ibcDenom)
	if v == nil {
		return errors.New("zkgm/voucher: not found: " + ibcDenom)
	}
	return v.ledger.Burn(address(sender), amountInt64(amount))
}

func VoucherBalanceOf(ibcDenom string, addr address) int64 {
	v := getVoucher(ibcDenom)
	if v == nil {
		return 0
	}
	return v.token.BalanceOf(addr)
}

func amountInt64(amount *u256.Uint) int64 {
	if !amount.IsUint64() || amount.Uint64() > uint64(math.MaxInt64) {
		panic("zkgm/voucher: amount overflows int64")
	}
	return amount.Int64()
}
