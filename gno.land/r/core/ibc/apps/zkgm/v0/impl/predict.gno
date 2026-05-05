package impl

import (
	"crypto/keccak256"
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
)

const ibcDenomPrefix = "ibc/"

const (
	tagZkgmV1 = "ZKGM_V1"
	tagZkgmV2 = "ZKGM_V2"
)

// PredictWrappedTokenV1 derives the wrapped IBC denom for a v1 token order.
func PredictWrappedTokenV1(channelID string, baseToken []byte) string {
	buf := make([]byte, 0, len(tagZkgmV1)+len(channelID)+len(baseToken))
	buf = append(buf, tagZkgmV1...)
	buf = append(buf, channelID...)
	buf = append(buf, baseToken...)
	h := keccak256.Sum256(buf)
	return ibcDenomPrefix + hex.EncodeToString(h[:20])
}

// PredictWrappedTokenV2 derives the wrapped IBC denom for a v2 token order,
// binding the on-chain denom to the metadata image so different metadata
// produces a distinct wrapped token.
func PredictWrappedTokenV2(channelID string, baseToken []byte, metadataImage [32]byte) string {
	buf := make([]byte, 0, len(tagZkgmV2)+len(channelID)+len(baseToken)+len(metadataImage))
	buf = append(buf, tagZkgmV2...)
	buf = append(buf, channelID...)
	buf = append(buf, baseToken...)
	buf = append(buf, metadataImage[:]...)
	h := keccak256.Sum256(buf)
	return ibcDenomPrefix + hex.EncodeToString(h[:20])
}

func MetadataImage(meta z.TokenMetadata) [32]byte {
	bz, err := z.EncodeTokenMetadata(meta)
	if err != nil {
		panic(err)
	}
	return keccak256.Sum256(bz)
}
