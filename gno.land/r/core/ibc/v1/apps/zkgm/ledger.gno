package zkgm

import (
	"chain/runtime"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
)

var (
	tokenOrigin      = bptree.NewBPTree32()
	metadataImageOf  = bptree.NewBPTree32()
	channelBalanceV2 = bptree.NewBPTree32()
)

func mustBeAuthorizedImpl() {
	caller := runtime.PreviousRealm().PkgPath()
	if !InAllowedImpls(caller) {
		panic("zkgm/ledger: caller is not an authorized impl: " + caller)
	}
}

// SetTokenOrigin records the channel-path that minted ibcDenom on this chain.
func SetTokenOrigin(cur realm, denom string, path *u256.Uint) {
	mustBeAuthorizedImpl()
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
	mustBeAuthorizedImpl()
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
	mustBeAuthorizedImpl()
	channelBalanceV2.Set(key, amount)
}

// RemoveChannelBalanceV2 deletes the channel balance entry once it drains to zero.
func RemoveChannelBalanceV2(cur realm, key string) {
	mustBeAuthorizedImpl()
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
