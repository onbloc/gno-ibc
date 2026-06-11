package impl

import (
	"errors"
	"strings"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
)

type assetClass uint8

const (
	classNative assetClass = iota
	classVoucher
	classLocalGRC20
)

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

func recordAssetClass(cur realm, denom string, c assetClass) {
	zkgm.RecordAssetClass(cross(cur), denom, uint8(c))
}

func assetClassFor(denom string) assetClass {
	if v, ok := zkgm.GetAssetClass(denom); ok {
		return assetClass(v)
	}
	// Compatibility fallback for pre-upgrade in-flight native/voucher orders.
	// New local-GRC20 escrow records its class before channel balance is credited,
	// so an unrecorded denom must not be reclassified by a later grc20reg entry.
	if strings.HasPrefix(denom, ibcDenomPrefix) {
		return classVoucher
	}
	return classNative
}

func escrowAsset(cur realm, denom string, sender string, amount *u256.Uint, budget *sentCoinBudget) error {
	liveClass := classify(denom)
	c := liveClass
	if value, ok := zkgm.GetAssetClass(denom); ok {
		c = assetClass(value)
		if c != liveClass {
			return errors.New("zkgm/v1: asset class changed for " + denom)
		}
	}
	switch c {
	case classVoucher:
		if err := zkgm.BurnVoucher(cross(cur), denom, sender, amount); err != nil {
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
	recordAssetClass(cur, denom, c)
	return nil
}

func releaseAsset(cur realm, denom string, recipient string, amount *u256.Uint) error {
	switch assetClassFor(denom) {
	case classVoucher:
		return refundIBCVoucher(cur, []byte(denom), recipient, amount)
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
