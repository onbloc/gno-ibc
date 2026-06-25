package impl

import (
	"encoding/hex"

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
	key := ChannelBalanceKeyV2(channelId, path, baseToken, quoteToken)

	curAmount, ok := v.store.GetChannelBalanceV2(key)
	if !ok || curAmount == nil {
		curAmount = u256.Zero()
	}

	// silently storing a smaller balance. This entrypoint returns no error,
	// so an overflow aborts the tx via panic.
	calculatedAmount, overflow := u256.Zero().AddOverflow(curAmount, amount)
	if overflow {
		panic(errChannelBalanceOverflow)
	}

	v.store.SetChannelBalanceV2(0, rlm, key, calculatedAmount)
}

// decreaseChannelBalanceV2 subtracts from the escrow balance, erroring on underflow and preserving a zero entry.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3241-L3268
func (v *ucs03ZkgmV1) decreaseChannelBalanceV2(_ int, rlm realm, channelId types.ChannelId, path *u256.Uint, baseToken, quoteToken []byte, amount *u256.Uint) error {
	key := ChannelBalanceKeyV2(channelId, path, baseToken, quoteToken)

	curAmount, ok := v.store.GetChannelBalanceV2(key)
	if !ok || curAmount == nil || curAmount.Cmp(amount) < 0 {
		return makeError(errChannelBalanceUnderflow)
	}

	// This entrypoint returns an error, so an underflow aborts the tx via return.
	calculatedAmount, underflow := u256.Zero().SubOverflow(curAmount, amount)
	if underflow {
		return makeError(errChannelBalanceUnderflow)
	}

	v.store.SetChannelBalanceV2(0, rlm, key, calculatedAmount)

	return nil
}
