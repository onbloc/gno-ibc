package impl

import (
	"crypto/keccak256"
	"encoding/hex"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	abi "gno.land/p/onbloc/encoding/abi"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

const (
	ibcDenomPrefix = "ibc/"
	tagCallProxy   = "ZKGM_CALL_PROXY"
)

var predictV1Schema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeUint256},
	{Type: abi.TypeUint32},
	{Type: abi.TypeBytes},
}}

var predictV2Schema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeUint256},
	{Type: abi.TypeUint32},
	{Type: abi.TypeBytes},
	{Type: abi.TypeUint256},
}}

// PredictWrappedTokenV1 derives the wrapped IBC denom for a v1 token order.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L1364-L1389
func PredictWrappedTokenV1(path *u256.Uint, channelId uint32, baseToken []byte) string {
	if path == nil {
		path = u256.Zero()
	}
	bz, err := abi.Encode(predictV1Schema, []any{path, channelId, baseToken})
	if err != nil {
		panic(err)
	}
	h := keccak256.Sum256(bz)
	return ibcDenomPrefix + hex.EncodeToString(h[:20])
}

// PredictWrappedTokenV2 derives the IBC voucher denom for a v2 token order.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3332-L3353
func PredictWrappedTokenV2(path *u256.Uint, channelId uint32, baseToken []byte, metadataImage [32]byte) string {
	if path == nil {
		path = u256.Zero()
	}
	image := new(u256.Uint).SetBytes(metadataImage[:])
	bz, err := abi.Encode(predictV2Schema, []any{path, channelId, baseToken, image})
	if err != nil {
		panic(err)
	}
	h := keccak256.Sum256(bz)
	return ibcDenomPrefix + hex.EncodeToString(h[:20])
}

// MetadataImage returns keccak256(TokenMetadata) — the on-chain identity of the
// metadata used to mint a voucher.
func MetadataImage(meta z.TokenMetadata) [32]byte {
	bz, err := z.EncodeTokenMetadata(meta)
	if err != nil {
		panic(err)
	}
	return keccak256.Sum256(bz)
}

// u256FromBytes32 reads a 32-byte big-endian value as a uint256.
func u256FromBytes32(bz [32]byte) *u256.Uint {
	return new(u256.Uint).SetBytes(bz[:])
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
	if path == nil {
		path = u256.Zero()
	}
	bz, err := abi.Encode(predictV1Schema, []any{path, uint32(channelId), sender})
	if err != nil {
		panic(err)
	}
	buf := make([]byte, 0, len(tagCallProxy)+len(bz))
	buf = append(buf, tagCallProxy...)
	buf = append(buf, bz...)

	h := keccak256.Sum256(buf)
	return "zkgm1" + hex.EncodeToString(h[:20])
}
