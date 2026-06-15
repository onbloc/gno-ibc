package impl

import (
	"chain"
	"errors"
	"strconv"
	"strings"

	u256 "gno.land/p/gnoswap/uint256"
)

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

type sentCoinBudget struct {
	coins []chain.Coin
}

func newSentCoinBudget(sent chain.Coins) *sentCoinBudget {
	b := &sentCoinBudget{coins: make([]chain.Coin, len(sent))}
	copy(b.coins, sent)
	return b
}

func (b *sentCoinBudget) consume(denom string, amount *u256.Uint) error {
	want, err := amountInt64(amount)
	if err != nil {
		return err
	}
	for i := range b.coins {
		if b.coins[i].Denom == denom {
			if b.coins[i].Amount < want {
				return errCoinMismatch
			}
			b.coins[i].Amount -= want
			return nil
		}
	}
	return errCoinMismatch
}

func (b *sentCoinBudget) drained() bool {
	for i := range b.coins {
		if b.coins[i].Amount != 0 {
			return false
		}
	}
	return true
}

func (b *sentCoinBudget) assertDrained() error {
	if !b.drained() {
		return errCoinMismatch
	}
	return nil
}

var errCoinMismatch = errors.New("zkgm/coins: sent coin mismatch")
