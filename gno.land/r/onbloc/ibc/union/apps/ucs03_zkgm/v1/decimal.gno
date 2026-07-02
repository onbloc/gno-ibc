package impl

import (
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

const targetDecimals = uint8(6)

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

// scaleUpAmount is currently unused
func scaleUpAmount(tokenDecimals uint8, amount *u256.Uint) (*u256.Uint, error) {
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

func scaleDownAmount(tokenDecimals uint8, amount *u256.Uint) (*u256.Uint, error) {
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

// scaleDownOrderAmounts scales BaseAmount and QuoteAmount from wire to local precision.
func scaleDownOrderAmounts(decimals uint8, order z.TokenOrderV2) (z.TokenOrderV2, error) {
	localBaseAmount, err := scaleDownAmount(decimals, order.BaseAmount)
	if err != nil {
		return order, err
	}

	localQuoteAmount, err := scaleDownAmount(decimals, order.QuoteAmount)
	if err != nil {
		return order, err
	}

	order.BaseAmount = localBaseAmount
	order.QuoteAmount = localQuoteAmount
	return order, nil
}
