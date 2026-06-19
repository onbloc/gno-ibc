package impl

import (
	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

const (
	ibcDenomPrefix = "ibc/"
)

// PredictWrappedToken derives the wrapped IBC denom for a v1 token order.
func PredictWrappedToken(path *u256.Uint, channelId uint32, baseToken []byte) string {
	return z.PredictWrappedToken(path, channelId, baseToken)
}

// PredictWrappedTokenV2 derives the IBC voucher denom for a v2 token order.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3332-L3353
func PredictWrappedTokenV2(path *u256.Uint, channelId uint32, baseToken []byte, metadataImage [32]byte) string {
	return z.PredictWrappedTokenV2(path, channelId, baseToken, metadataImage)
}

// MetadataImage returns keccak256(TokenMetadata) — the on-chain identity of the
// metadata used to mint a voucher.
func MetadataImage(meta z.TokenMetadata) [32]byte {
	return z.MetadataImage(meta)
}

// u256FromBytes32 reads a 32-byte big-endian value as a uint256.
func u256FromBytes32(bz [32]byte) *u256.Uint {
	return z.Uint256FromBytes32(bz)
}

// PredictCallProxyAccount returns the synthetic Gno address that represents
// the given (path, destinationChannel, sender) tuple as a callable account.
// key = zkgm1<first-20-bytes-of-keccak(ZKGM_CALL_PROXY || abi.encode(path, channelId, sender))>
//
// The ABI-encoding of the (uint256, uint32, bytes) tuple mirrors union's
// proxy_account_salt preimage and, being length-prefixed/offset-encoded, is
// injective in all three components (unlike a raw concatenation). The fixed
// ZKGM_CALL_PROXY tag domain-separates it from the wrapped-token derivations.
func PredictCallProxyAccount(path *u256.Uint, channelId types.ChannelId, sender []byte) string {
	return z.PredictCallProxyAccount(path, channelId, sender)
}
