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

func requireSentCoin(sent chain.Coins, denom string, amount *u256.Uint) error {
	want := amountInt64(amount)
	if len(sent) != 1 || sent[0].Denom != denom || sent[0].Amount != want {
		return errCoinMismatch
	}
	return nil
}

var errCoinMismatch = errors.New("zkgm/coins: sent coin mismatch")
