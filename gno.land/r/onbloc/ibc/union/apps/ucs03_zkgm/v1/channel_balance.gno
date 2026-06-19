package impl

import (
	"encoding/hex"
	"errors"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
)

// ChannelBalanceKeyV2 returns the storage key for a v2 channel balance entry.
func ChannelBalanceKeyV2(channelId types.ChannelId, path *u256.Uint, baseToken, quoteToken []byte) string {
	return channelId.String() + "/" + path.ToString() + "/" + hex.EncodeToString(baseToken) + "/" + hex.EncodeToString(quoteToken)
}

// increaseChannelBalanceV2 adds amount to the (channel, path, base, quote) escrow balance.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3272-L3299
func (v *ucs03ZkgmV1) increaseChannelBalanceV2(_ int, rlm realm, channelId types.ChannelId, path *u256.Uint, baseToken, quoteToken []byte, amount *u256.Uint) {
	if amount.IsZero() {
		return
	}
	key := ChannelBalanceKeyV2(channelId, path, baseToken, quoteToken)
	curAmount, ok := v.store.GetChannelBalanceV2(key)
	if !ok || curAmount == nil {
		curAmount = u256.Zero()
	}
	v.store.SetChannelBalanceV2(0, rlm, key, new(u256.Uint).Add(curAmount, amount))
}

// decreaseChannelBalanceV2 subtracts from the escrow balance, erroring on underflow and clearing the entry on zero.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3241-L3268
func (v *ucs03ZkgmV1) decreaseChannelBalanceV2(_ int, rlm realm, channelId types.ChannelId, path *u256.Uint, baseToken, quoteToken []byte, amount *u256.Uint) error {
	if amount.IsZero() {
		return nil
	}
	key := ChannelBalanceKeyV2(channelId, path, baseToken, quoteToken)
	curAmount, ok := v.store.GetChannelBalanceV2(key)
	if !ok || curAmount == nil || curAmount.Cmp(amount) < 0 {
		return errors.New("zkgm/channel_balance: underflow")
	}
	next := new(u256.Uint).Sub(curAmount, amount)
	if next.IsZero() {
		v.store.RemoveChannelBalanceV2(0, rlm, key)
	} else {
		v.store.SetChannelBalanceV2(0, rlm, key, next)
	}
	return nil
}
