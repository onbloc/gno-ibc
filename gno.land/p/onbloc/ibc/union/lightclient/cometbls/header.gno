package cometbls

import (
	"errors"

	abienc "gno.land/p/onbloc/encoding/abi"
)

// Ethereum ABI wire format for Union CometBLS Header.
//
// Encoding rules (Solidity params tuple form):
//   - Header: 8 static words + dynamic ZKP

// [0-2] uint64 x 3  [3-5] bytes32 x 3  [6] uint64  [7] bytes (dynamic ZKP)
var headerSchema = abienc.Schema{Fields: []abienc.Field{
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeBytes32},
	{Type: abienc.TypeBytes32},
	{Type: abienc.TypeBytes32},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeBytes},
}}

// EncodeHeader ABI-encodes a Header.
// ValidatorsHash and AppHash must each be exactly 32 bytes.
func EncodeHeader(h Header) ([]byte, error) {
	lh := h.SignedHeader
	vh, err := toBytes32(lh.ValidatorsHash, "validators hash")
	if err != nil {
		return nil, err
	}
	ah, err := toBytes32(lh.AppHash, "app hash")
	if err != nil {
		return nil, err
	}
	return abienc.Encode(headerSchema, []any{
		uint64(lh.Height),
		uint64(lh.TimeSeconds),
		uint64(lh.TimeNanos),
		vh, [32]byte(lh.NextValidatorsHash), ah,
		h.TrustedHeight,
		h.ZeroKnowledgeProof,
	})
}

func DecodeHeader(buf []byte) (Header, error) {
	vals, err := abienc.Decode(headerSchema, buf)
	if err != nil {
		return Header{}, errors.New("cometbls: " + err.Error())
	}
	var h Header
	h.SignedHeader.Height = int64(vals[0].(uint64))
	h.SignedHeader.TimeSeconds = int64(vals[1].(uint64))
	h.SignedHeader.TimeNanos, err = validateTimeNanos(vals[2].(uint64))
	if err != nil {
		return Header{}, err
	}
	vh := vals[3].([32]byte)
	h.SignedHeader.ValidatorsHash = vh[:]
	nvh := vals[4].([32]byte)
	h.SignedHeader.NextValidatorsHash = H256(nvh)
	ah := vals[5].([32]byte)
	h.SignedHeader.AppHash = ah[:]
	h.TrustedHeight = vals[6].(uint64)
	h.ZeroKnowledgeProof = vals[7].([]byte)
	return h, nil
}
