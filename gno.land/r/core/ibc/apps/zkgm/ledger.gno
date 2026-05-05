package zkgm

import (
	"chain/runtime"

	"gno.land/p/aib/ibc/types"
	tb "gno.land/p/gnoswap/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
)

var (
	tokenOrigin        = bptree.NewBPTree32()
	metadataImageOf    = bptree.NewBPTree32()
	hashToForeignToken = bptree.NewBPTree32()
	channelBalanceV2   = bptree.NewBPTree32()
	inFlightPacket     = bptree.NewBPTree32()
	tokenBucket        = bptree.NewBPTree32()
	rateLimitDisabled  bool
)

func mustBeAuthorizedImpl() {
	caller := runtime.PreviousRealm().PkgPath()
	if !InAllowedImpls(caller) {
		panic("zkgm/ledger: caller is not an authorized impl: " + caller)
	}
}

func SetTokenOrigin(cur realm, denom string, path *u256.Uint) {
	mustBeAuthorizedImpl()
	tokenOrigin.Set(denom, path)
}

func GetTokenOrigin(denom string) (*u256.Uint, bool) {
	value, ok := tokenOrigin.Get(denom)
	if !ok {
		return nil, false
	}
	return value.(*u256.Uint), true
}

func HasTokenOrigin(denom string) bool {
	return tokenOrigin.Has(denom)
}

func RemoveTokenOrigin(cur realm, denom string) {
	mustBeAuthorizedImpl()
	tokenOrigin.Remove(denom)
}

func SetMetadataImageOf(cur realm, denom string, image [32]byte) {
	mustBeAuthorizedImpl()
	metadataImageOf.Set(denom, image)
}

func GetMetadataImageOf(denom string) ([32]byte, bool) {
	value, ok := metadataImageOf.Get(denom)
	if !ok {
		return [32]byte{}, false
	}
	return value.([32]byte), true
}

func RemoveMetadataImageOf(cur realm, denom string) {
	mustBeAuthorizedImpl()
	metadataImageOf.Remove(denom)
}

func SetHashToForeignToken(cur realm, hash string, token []byte) {
	mustBeAuthorizedImpl()
	hashToForeignToken.Set(hash, token)
}

func GetHashToForeignToken(hash string) ([]byte, bool) {
	value, ok := hashToForeignToken.Get(hash)
	if !ok {
		return nil, false
	}
	return value.([]byte), true
}

func RemoveHashToForeignToken(cur realm, hash string) {
	mustBeAuthorizedImpl()
	hashToForeignToken.Remove(hash)
}

func SetChannelBalanceV2(cur realm, key string, amount *u256.Uint) {
	mustBeAuthorizedImpl()
	channelBalanceV2.Set(key, amount)
}

func RemoveChannelBalanceV2(cur realm, key string) {
	mustBeAuthorizedImpl()
	channelBalanceV2.Remove(key)
}

func SetInFlightPacket(cur realm, packetHash string, packet types.Packet) {
	mustBeAuthorizedImpl()
	inFlightPacket.Set(packetHash, packet)
}

func GetInFlightPacket(packetHash string) (types.Packet, bool) {
	value, ok := inFlightPacket.Get(packetHash)
	if !ok {
		return types.Packet{}, false
	}
	return value.(types.Packet), true
}

func RemoveInFlightPacket(cur realm, packetHash string) {
	mustBeAuthorizedImpl()
	inFlightPacket.Remove(packetHash)
}

func SetTokenBucket(cur realm, denom string, bucket *tb.TokenBucket) {
	mustBeAuthorizedImpl()
	tokenBucket.Set(denom, bucket)
}

func RemoveTokenBucket(cur realm, denom string) {
	mustBeAuthorizedImpl()
	tokenBucket.Remove(denom)
}

func RateLimit(cur realm, denom string, amount *u256.Uint, now *u256.Uint) error {
	mustBeAuthorizedImpl()
	if rateLimitDisabled {
		return nil
	}
	bucket := GetTokenBucket(denom)
	if bucket == nil {
		return nil
	}
	return bucket.RateLimit(amount, now)
}
