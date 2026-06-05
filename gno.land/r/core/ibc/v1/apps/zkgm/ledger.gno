package zkgm

import (
	"time"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	tb "gno.land/p/onbloc/tokenbucket"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

var (
	tokenOrigin       = bptree.NewBPTree32()
	metadataImageOf   = bptree.NewBPTree32()
	channelBalanceV2  = bptree.NewBPTree32()
	inFlightPackets   = bptree.NewBPTree32()
	tokenBucket       = bptree.NewBPTree32()
	rateLimitDisabled = false
)

func mustBeAuthorizedImpl(cur realm) {
	caller := cur.Previous().PkgPath()
	if !isAuthorizedImpl(caller) {
		panic("zkgm/ledger: caller is not an authorized impl: " + caller)
	}
}

// SetTokenOrigin records the channel-path that minted ibcDenom on this chain.
func SetTokenOrigin(cur realm, denom string, path *u256.Uint) {
	mustBeAuthorizedImpl(cur)
	tokenOrigin.Set(denom, path)
}

// GetTokenOrigin returns the recorded mint-path for ibcDenom, if any.
func GetTokenOrigin(denom string) (*u256.Uint, bool) {
	value, ok := tokenOrigin.Get(denom)
	if !ok {
		return nil, false
	}
	return value.(*u256.Uint), true
}

// SetMetadataImageOf records the keccak metadata image associated with ibcDenom.
func SetMetadataImageOf(cur realm, denom string, image [32]byte) {
	mustBeAuthorizedImpl(cur)
	metadataImageOf.Set(denom, image)
}

// GetMetadataImageOf returns the metadata image for ibcDenom, if any.
func GetMetadataImageOf(denom string) ([32]byte, bool) {
	value, ok := metadataImageOf.Get(denom)
	if !ok {
		return [32]byte{}, false
	}
	return value.([32]byte), true
}

// SetChannelBalanceV2 stores the per-(channel,path,base,quote) escrow balance.
func SetChannelBalanceV2(cur realm, key string, amount *u256.Uint) {
	mustBeAuthorizedImpl(cur)
	channelBalanceV2.Set(key, amount)
}

// RemoveChannelBalanceV2 deletes the channel balance entry once it drains to zero.
func RemoveChannelBalanceV2(cur realm, key string) {
	mustBeAuthorizedImpl(cur)
	channelBalanceV2.Remove(key)
}

// GetChannelBalanceV2 returns the stored balance for key, or nil if absent.
func GetChannelBalanceV2(key string) *u256.Uint {
	value, ok := channelBalanceV2.Get(key)
	if !ok {
		return nil
	}
	return value.(*u256.Uint)
}

// SetInFlightPacket records a forwarded child packet and its parent async packet.
func SetInFlightPacket(cur realm, key InFlightKey, value InFlightValue) {
	mustBeAuthorizedImpl(cur)
	inFlightPackets.Set(inFlightKeyString(key), value)
	emitZkgmForwardInFlightSetEvent(key.PacketHash, core.CommitPacket(value.ParentPacket))
}

// GetInFlightPacket returns the parent packet for a forwarded child, if any.
func GetInFlightPacket(key InFlightKey) (InFlightValue, bool) {
	value, ok := inFlightPackets.Get(inFlightKeyString(key))
	if !ok {
		return InFlightValue{}, false
	}
	return value.(InFlightValue), true
}

// PopInFlightPacket returns and removes a forwarded child mapping, if any.
func PopInFlightPacket(cur realm, key InFlightKey) (InFlightValue, bool) {
	mustBeAuthorizedImpl(cur)
	value, ok := inFlightPackets.Remove(inFlightKeyString(key))
	if !ok {
		emitZkgmForwardInFlightPoppedEvent(key.PacketHash, false)
		return InFlightValue{}, false
	}
	emitZkgmForwardInFlightPoppedEvent(key.PacketHash, true)
	return value.(InFlightValue), true
}

func inFlightKeyString(key InFlightKey) string {
	return key.PacketHash.String()
}

// SetTokenBucket stores the rate-limit bucket for denom.
func SetTokenBucket(cur realm, denom string, bucket *tb.TokenBucket) {
	mustBeAuthorizedImpl(cur)
	tokenBucket.Set(denom, bucket)
}

// RemoveTokenBucket removes the rate-limit bucket for denom.
func RemoveTokenBucket(cur realm, denom string) {
	mustBeAuthorizedImpl(cur)
	tokenBucket.Remove(denom)
}

// GetTokenBucket returns the rate-limit bucket for denom, if configured.
func GetTokenBucket(denom string) *tb.TokenBucket {
	value, ok := tokenBucket.Get(denom)
	if !ok {
		return nil
	}

	return value.(*tb.TokenBucket)
}

// RateLimit charges amount from denom's bucket when rate limiting is enabled.
// `now` is sourced from block time (time.Now().Unix()), so RefillRate is
// interpreted as tokens per second.
func RateLimit(cur realm, denom string, amount *u256.Uint) error {
	mustBeAuthorizedImpl(cur)

	if rateLimitDisabled || amount == nil {
		return nil
	}

	bucket := GetTokenBucket(denom)
	if bucket == nil {
		return nil
	}

	return bucket.RateLimit(amount, blockNow())
}

func blockNow() *u256.Uint {
	return u256.NewUint(uint64(time.Now().Unix()))
}
