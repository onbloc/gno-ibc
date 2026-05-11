package impl

import (
	"encoding/hex"
	"errors"

	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

// ChannelBalanceKeyV2 returns the storage key for a v2 channel balance entry.
func ChannelBalanceKeyV2(channelId core.ChannelId, path *u256.Uint, baseToken, quoteToken []byte) string {
	return channelId.String() + "/" + path.ToString() + "/" + hex.EncodeToString(baseToken) + "/" + hex.EncodeToString(quoteToken)
}

func increaseChannelBalanceV2(cur realm, channelId core.ChannelId, path *u256.Uint, baseToken, quoteToken []byte, amount *u256.Uint) {
	if amount.IsZero() {
		return
	}
	key := ChannelBalanceKeyV2(channelId, path, baseToken, quoteToken)
	curAmount := zkgm.GetChannelBalanceV2(key)
	if curAmount == nil {
		curAmount = u256.Zero()
	}
	zkgm.SetChannelBalanceV2(cross, key, new(u256.Uint).Add(curAmount, amount))
}

func decreaseChannelBalanceV2(cur realm, channelId core.ChannelId, path *u256.Uint, baseToken, quoteToken []byte, amount *u256.Uint) error {
	if amount.IsZero() {
		return nil
	}
	key := ChannelBalanceKeyV2(channelId, path, baseToken, quoteToken)
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
