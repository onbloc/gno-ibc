package impl

import (
	"chain"
	"errors"
	"strconv"
	"strings"

	u256 "gno.land/p/gnoswap/uint256"
)

// parseCoins parses a comma-separated <amount><denom> string into Coins.
func parseCoins(s string) chain.Coins {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	coins := make([]chain.Coin, 0, len(parts))
	for _, part := range parts {
		if part == "" {
			continue
		}
		i := 0
		for i < len(part) && part[i] >= '0' && part[i] <= '9' {
			i++
		}
		if i == 0 || i == len(part) {
			panic("zkgm/coins: invalid coin " + part)
		}
		amount, err := strconv.ParseInt(part[:i], 10, 64)
		if err != nil {
			panic(err)
		}
		coins = append(coins, chain.NewCoin(part[i:], amount))
	}
	return chain.NewCoins(coins...)
}

// funds is the gno analog of the reference contract's threaded `funds: &mut Coins`
// (the message's attached coins). It is decremented as each token order consumes
// its BaseAmount during verification.
type funds struct {
	coins []chain.Coin
}

// newFunds snapshots the attached coins into a mutable spend budget.
func newFunds(sent chain.Coins) *funds {
	f := &funds{coins: make([]chain.Coin, len(sent))}
	copy(f.coins, sent)
	return f
}

// sub deducts amount of denom from the attached funds, mirroring funds.sub(coin)
// in the reference contract. It errors when the funds do not cover the amount.
func (f *funds) sub(denom string, amount *u256.Uint) error {
	want, err := amountInt64(amount)
	if err != nil {
		return err
	}
	for i := range f.coins {
		if f.coins[i].Denom == denom {
			if f.coins[i].Amount < want {
				return errCoinMismatch
			}
			f.coins[i].Amount -= want
			return nil
		}
	}
	return errCoinMismatch
}

// isEmpty reports whether every attached coin has been fully consumed.
func (f *funds) isEmpty() bool {
	for i := range f.coins {
		if f.coins[i].Amount != 0 {
			return false
		}
	}
	return true
}

// assertEmpty errors when any attached coin is left unconsumed.
func (f *funds) assertEmpty() error {
	if !f.isEmpty() {
		return errCoinMismatch
	}
	return nil
}

var errCoinMismatch = errors.New("zkgm/coins: sent coin mismatch")
