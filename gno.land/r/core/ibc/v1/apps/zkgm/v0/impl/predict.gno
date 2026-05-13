package impl

import (
	"crypto/keccak256"
	"encoding/hex"

	abi "gno.land/p/core/encoding/abi"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
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

func u256FromBytes32(bz [32]byte) *u256.Uint {
	return new(u256.Uint).SetBytes(bz[:])
}

// PredictCallProxyAccount returns the synthetic Gno address that represents
// the given (path, destinationChannel, sender) tuple as a callable account.
// key = zkgm1<first-20-bytes-of-keccak(ZKGM_CALL_PROXY || path || channelId || sender)>
func PredictCallProxyAccount(path *u256.Uint, channelId core.ChannelId, sender []byte) string {
	var pathBytes [32]byte
	if path != nil {
		pathBytes = z.Uint256ToBytes32(path)
	}
	channel := channelId.String()
	buf := make([]byte, 0, len(tagCallProxy)+len(pathBytes)+len(channel)+len(sender))
	buf = append(buf, tagCallProxy...)
	buf = append(buf, pathBytes[:]...)
	buf = append(buf, channel...)
	buf = append(buf, sender...)

	h := keccak256.Sum256(buf)
	return "zkgm1" + hex.EncodeToString(h[:20])
}
