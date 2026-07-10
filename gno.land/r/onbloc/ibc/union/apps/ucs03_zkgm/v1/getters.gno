package v1

import (
	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// getters.gno implements the read-only IAppGetter surface. Results read the
// injected proxy store and return snapshots so callers do not receive mutable
// proxy-owned pointers.

// GetTokenBucket returns the rate-limit bucket configured for denom.
func (v *ucs03ZkgmV1) GetTokenBucket(denom string) (*tb.TokenBucket, error) {
	bucket, ok := v.store.GetTokenBucket(denom)
	if !ok || bucket == nil {
		return nil, makeError(zkgm.ErrTokenBucketNotFound, denom)
	}

	return cloneTokenBucket(bucket), nil
}

// GetChannelBalanceV2 returns the escrow balance for the v2 channel-balance key.
func (v *ucs03ZkgmV1) GetChannelBalanceV2(channelId types.ChannelId, path *u256.Uint, baseToken string, quoteToken []byte) (*u256.Uint, error) {
	balance, ok := v.store.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, path, []byte(baseToken), quoteToken))
	if !ok || balance == nil {
		return nil, makeError(zkgm.ErrChannelBalanceV2NotFound, channelId.String())
	}

	return balance.Clone(), nil
}

func cloneTokenBucket(bucket *tb.TokenBucket) *tb.TokenBucket {
	return &tb.TokenBucket{
		Capacity:   bucket.Capacity.Clone(),
		Available:  bucket.Available.Clone(),
		RefillRate: bucket.RefillRate.Clone(),
		LastRefill: bucket.LastRefill.Clone(),
	}
}
