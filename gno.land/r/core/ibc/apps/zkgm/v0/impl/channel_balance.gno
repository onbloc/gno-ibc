package impl

import (
	"encoding/hex"
	"errors"

	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

func ChannelBalanceKeyV2(channelID string, path *u256.Uint, baseToken, quoteToken []byte) string {
	return channelID + "/" + path.ToString() + "/" + hex.EncodeToString(baseToken) + "/" + hex.EncodeToString(quoteToken)
}

func increaseChannelBalanceV2(cur realm, channelID string, path *u256.Uint, baseToken, quoteToken []byte, amount *u256.Uint) {
	if amount.IsZero() {
		return
	}
	key := ChannelBalanceKeyV2(channelID, path, baseToken, quoteToken)
	curAmount := zkgm.GetChannelBalanceV2(key)
	if curAmount == nil {
		curAmount = u256.NewUint(0)
	}
	zkgm.SetChannelBalanceV2(cross, key, new(u256.Uint).Add(curAmount, amount))
}

func decreaseChannelBalanceV2(cur realm, channelID string, path *u256.Uint, baseToken, quoteToken []byte, amount *u256.Uint) error {
	if amount.IsZero() {
		return nil
	}
	key := ChannelBalanceKeyV2(channelID, path, baseToken, quoteToken)
	curAmount := zkgm.GetChannelBalanceV2(key)
	if curAmount == nil || curAmount.Cmp(amount) < 0 {
		return errors.New("zkgm/channel_balance: underflow")
	}
	next := new(u256.Uint).Sub(curAmount, amount)
	if next.IsZero() {
		zkgm.RemoveChannelBalanceV2(cross, key)
	} else {
		zkgm.SetChannelBalanceV2(cross, key, next)
	}
	return nil
}
