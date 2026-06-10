package zkgm

import (
	"errors"
	"math"
	"strings"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/r/demo/defi/grc20reg"
)

const ibcDenomPrefix = "ibc/"

type voucher struct {
	token  *grc20.Token
	ledger *grc20.PrivateLedger
}

var voucherTokens = bptree.NewBPTree32()

var (
	errVoucherAmountOverflow = errors.New("zkgm/voucher: amount overflows int64")
	errVoucherNotFound       = errors.New("zkgm/voucher: not found")
)

func MintVoucher(cur realm, ibcDenom string, baseDenom string, metadataImage [32]byte, name, symbol string, decimals uint8, receiver string, amount *u256.Uint) error {
	_ = baseDenom
	requireVoucherMutator(cur, "mint voucher")
	n, err := voucherAmountInt64(amount)
	if err != nil {
		return err
	}

	// Symbol policy stays in the active impl; proxy stores voucher state and
	// expects authorized impls to pass a GRC20-valid symbol.
	v := getOrCreateVoucher(cur, ibcDenom, metadataImage, name, symbol, decimals)
	return v.ledger.Mint(address(receiver), n)
}

func BurnVoucher(cur realm, ibcDenom string, sender string, amount *u256.Uint) error {
	requireVoucherMutator(cur, "burn voucher")
	n, err := voucherAmountInt64(amount)
	if err != nil {
		return err
	}
	v := getVoucher(ibcDenom)
	if v == nil {
		return errors.New(errVoucherNotFound.Error() + ": " + ibcDenom)
	}
	return v.ledger.Burn(address(sender), n)
}

func TransferVoucher(cur realm, ibcDenom string, from address, to address, amount *u256.Uint) error {
	requireVoucherMutator(cur, "transfer voucher")
	n, err := voucherAmountInt64(amount)
	if err != nil {
		return err
	}
	v := getVoucher(ibcDenom)
	if v == nil {
		return errors.New(errVoucherNotFound.Error() + ": " + ibcDenom)
	}
	return v.ledger.Transfer(from, to, n)
}

func HasVoucher(ibcDenom string) bool {
	return getVoucher(ibcDenom) != nil
}

func VoucherBalanceOf(ibcDenom string, addr address) int64 {
	v := getVoucher(ibcDenom)
	if v == nil {
		return 0
	}
	return v.token.BalanceOf(addr)
}

func VoucherNameOf(ibcDenom string) string {
	v := getVoucher(ibcDenom)
	if v == nil {
		return ""
	}
	return v.token.GetName()
}

func VoucherSymbolOf(ibcDenom string) string {
	v := getVoucher(ibcDenom)
	if v == nil {
		return ""
	}
	return v.token.GetSymbol()
}

func VoucherDecimalsOf(ibcDenom string) int {
	v := getVoucher(ibcDenom)
	if v == nil {
		return 0
	}
	return v.token.GetDecimals()
}

func voucherAmountInt64(amount *u256.Uint) (int64, error) {
	if !amount.IsUint64() || amount.Uint64() > uint64(math.MaxInt64) {
		return 0, errVoucherAmountOverflow
	}
	return amount.Int64(), nil
}

func getOrCreateVoucher(cur realm, ibcDenom string, metadataImage [32]byte, name, symbol string, decimals uint8) *voucher {
	if v, ok := voucherTokens.Get(ibcDenom); ok {
		return v.(*voucher)
	}

	if name == "" {
		name = ibcDenom
	}

	token, ledger := grc20.NewToken(0, cur, name, symbol, int(decimals))
	grc20reg.Register(cross(cur), token, strings.TrimPrefix(ibcDenom, ibcDenomPrefix))

	v := &voucher{token: token, ledger: ledger}
	voucherTokens.Set(ibcDenom, v)
	SetMetadataImageOf(cur, ibcDenom, metadataImage)
	return v
}

func getVoucher(ibcDenom string) *voucher {
	v, ok := voucherTokens.Get(ibcDenom)
	if !ok {
		return nil
	}
	return v.(*voucher)
}

func requireVoucherMutator(cur realm, action string) {
	// The loader model may bind implPath to a loader realm while token-order
	// execution runs from the v0/impl realm. Match proxy ledger writers:
	// registered impl and allowlisted impl realms may mutate voucher state.
	requireImplRealm(cur, action)
}
