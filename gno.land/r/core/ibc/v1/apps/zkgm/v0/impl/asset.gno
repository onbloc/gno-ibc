package impl

import (
	"strings"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
)

type assetClass uint8

const (
	classNative assetClass = iota
	classVoucher
	classLocalGRC20
)

var assetClassOf = bptree.NewBPTree32()

func classify(denom string) assetClass {
	// Voucher wire denoms are `ibc/<hash>`, while their grc20reg keys use the
	// voucher realm path and hash slug. Check the prefix before registry lookup.
	if strings.HasPrefix(denom, ibcDenomPrefix) {
		return classVoucher
	}
	if grc20reg.Get(denom) != nil {
		return classLocalGRC20
	}
	return classNative
}

func recordAssetClass(denom string, c assetClass) {
	if _, ok := assetClassOf.Get(denom); ok {
		return
	}
	assetClassOf.Set(denom, c)
}

func assetClassFor(denom string) assetClass {
	if v, ok := assetClassOf.Get(denom); ok {
		return v.(assetClass)
	}
	// Compatibility fallback for pre-upgrade in-flight native/voucher orders.
	// New local-GRC20 escrow records its class before channel balance is credited.
	return classify(denom)
}

func escrowAsset(cur realm, denom string, sender string, amount *u256.Uint, budget *sentCoinBudget) error {
	c := classify(denom)
	switch c {
	case classVoucher:
		if err := burnVoucher(cross(cur), denom, sender, amount); err != nil {
			return err
		}
	case classLocalGRC20:
		n, err := amountInt64(amount)
		if err != nil {
			return err
		}
		if err := zkgm.EscrowGRC20(cross(cur), denom, address(sender), n); err != nil {
			return err
		}
	case classNative:
		if err := budget.consume(denom, amount); err != nil {
			return err
		}
	}
	recordAssetClass(denom, c)
	return nil
}

func releaseAsset(cur realm, denom string, recipient string, amount *u256.Uint) error {
	switch assetClassFor(denom) {
	case classLocalGRC20:
		n, err := amountInt64(amount)
		if err != nil {
			return err
		}
		return zkgm.ReleaseGRC20(cross(cur), denom, address(recipient), n)
	default:
		return sendNative(cur, denom, recipient, amount)
	}
}
