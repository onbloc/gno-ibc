package impl

import (
	"crypto/keccak256"
	"encoding/hex"

	abi "gno.land/p/core/encoding/abi"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
)

const ibcDenomPrefix = "ibc/"

const (
	tagCallProxy = "ZKGM_CALL_PROXY"
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
func PredictWrappedTokenV1(path *u256.Uint, channelID uint32, baseToken []byte) string {
	if path == nil {
		path = u256.Zero()
	}
	bz, err := abi.Encode(predictV1Schema, []any{path, channelID, baseToken})
	if err != nil {
		panic(err)
	}
	h := keccak256.Sum256(bz)
	return ibcDenomPrefix + hex.EncodeToString(h[:20])
}

// PredictWrappedTokenV2 derives the wrapped IBC denom for a v2 token order.
func PredictWrappedTokenV2(path *u256.Uint, channelID uint32, baseToken []byte, metadataImage [32]byte) string {
	if path == nil {
		path = u256.Zero()
	}
	image := new(u256.Uint).SetBytes(metadataImage[:])
	bz, err := abi.Encode(predictV2Schema, []any{path, channelID, baseToken, image})
	if err != nil {
		panic(err)
	}
	h := keccak256.Sum256(bz)
	return ibcDenomPrefix + hex.EncodeToString(h[:20])
}

func MetadataImage(meta z.TokenMetadata) [32]byte {
	bz, err := z.EncodeTokenMetadata(meta)
	if err != nil {
		panic(err)
	}
	return keccak256.Sum256(bz)
}

// PredictCallProxyAccount derives the deterministic caller account for a
// ZKGM Call dispatched on (path, channelID, sender).
func PredictCallProxyAccount(path *u256.Uint, channelID string, sender []byte) string {
	var pathBytes [32]byte
	if path != nil {
		pathBytes = z.Uint256ToBytes32(path)
	}
	buf := make([]byte, 0, len(tagCallProxy)+len(pathBytes)+len(channelID)+len(sender))
	buf = append(buf, tagCallProxy...)
	buf = append(buf, pathBytes[:]...)
	buf = append(buf, channelID...)
	buf = append(buf, sender...)
	h := keccak256.Sum256(buf)
	return "zkgm1" + hex.EncodeToString(h[:20])
}
