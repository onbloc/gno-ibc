package cometbls

import (
	"errors"

	abienc "gno.land/p/core/encoding/abi"
)

// Ethereum ABI wire format for Union CometBLS light client types.
//
// Encoding rules (Solidity params tuple form):
//   - ClientState:    6 words × 32 bytes = 192 bytes (all static)
//   - ConsensusState: 3 words × 32 bytes = 96 bytes  (all static)
//   - Header:         8 static words + dynamic ZKP
//   - Misbehaviour:   protobuf (ABI encoding is a TODO in Union)

var (
	// [0] chain_id bytes32  [1-4] uint64 × 4  [5] contract_address bytes32
	clientStateSchema = abienc.Schema{Fields: []abienc.Field{
		{Type: abienc.TypeBytes32},
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeBytes32},
	}}

	// [0] timestamp uint64  [1-2] bytes32 × 2
	consensusStateSchema = abienc.Schema{Fields: []abienc.Field{
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeBytes32},
		{Type: abienc.TypeBytes32},
	}}

	// [0-2] uint64 × 3  [3-5] bytes32 × 3  [6] uint64  [7] bytes (dynamic ZKP)
	headerSchema = abienc.Schema{Fields: []abienc.Field{
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeBytes32},
		{Type: abienc.TypeBytes32},
		{Type: abienc.TypeBytes32},
		{Type: abienc.TypeUint64},
		{Type: abienc.TypeBytes},
	}}
)

func EncodeClientState(cs ClientState) []byte {
	var chainID [32]byte
	n := len(cs.ChainID)
	if n > 32 {
		n = 32
	}
	copy(chainID[:], cs.ChainID[:n])
	contractAddress := [32]byte(cs.ContractAddress)
	buf, _ := abienc.Encode(clientStateSchema, []any{
		chainID,
		cs.TrustingPeriod,
		cs.MaxClockDrift,
		cs.FrozenHeight,
		cs.LatestHeight,
		contractAddress,
	})
	return buf
}

func DecodeClientState(buf []byte) (ClientState, error) {
	vals, err := abienc.Decode(clientStateSchema, buf)
	if err != nil {
		return ClientState{}, errors.New("cometbls: " + err.Error())
	}
	var cs ClientState
	chainID := vals[0].([32]byte)
	end := 32
	for end > 0 && chainID[end-1] == 0 {
		end--
	}
	cs.ChainID = string(chainID[:end])
	cs.TrustingPeriod = vals[1].(uint64)
	cs.MaxClockDrift = vals[2].(uint64)
	cs.FrozenHeight = vals[3].(uint64)
	cs.LatestHeight = vals[4].(uint64)
	cs.ContractAddress = H256(vals[5].([32]byte))
	return cs, nil
}

// EncodeConsensusState ABI-encodes a ConsensusState (96 bytes).
// Root.Hash must be exactly 32 bytes.
func EncodeConsensusState(cs ConsensusState) ([]byte, error) {
	appHash, err := toBytes32(cs.Root.Hash, "root hash")
	if err != nil {
		return nil, err
	}
	return abienc.Encode(consensusStateSchema, []any{cs.Timestamp, appHash, [32]byte(cs.NextValidatorsHash)})
}

func DecodeConsensusState(buf []byte) (ConsensusState, error) {
	vals, err := abienc.Decode(consensusStateSchema, buf)
	if err != nil {
		return ConsensusState{}, errors.New("cometbls: " + err.Error())
	}
	var cs ConsensusState
	cs.Timestamp = vals[0].(uint64)
	ah := vals[1].([32]byte)
	cs.Root.Hash = ah[:]
	nvh := vals[2].([32]byte)
	cs.NextValidatorsHash = H256(nvh)
	return cs, nil
}

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
	h.SignedHeader.TimeNanos = int32(vals[2].(uint64))
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

// EncodeMisbehaviour protobuf-encodes a Misbehaviour.
// ABI encoding for Misbehaviour is a TODO in Union; protobuf format is kept.
func EncodeMisbehaviour(m Misbehaviour) []byte {
	var buf []byte
	buf = pbAppendMsg(buf, 1, pbEncodeHeader(m.HeaderA))
	buf = pbAppendMsg(buf, 2, pbEncodeHeader(m.HeaderB))
	return buf
}

// DecodeMisbehaviour protobuf-decodes a Misbehaviour from buf.
func DecodeMisbehaviour(buf []byte) (Misbehaviour, error) {
	var m Misbehaviour
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return m, err
		}
		switch fieldNum {
		case 1:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return m, err
			}
			m.HeaderA, err = pbDecodeHeader(b)
			if err != nil {
				return m, err
			}
		case 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return m, err
			}
			m.HeaderB, err = pbDecodeHeader(b)
			if err != nil {
				return m, err
			}
		default:
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return m, err
			}
		}
	}
	return m, nil
}

func toBytes32(b []byte, name string) ([32]byte, error) {
	if len(b) != 32 {
		return [32]byte{}, errors.New("cometbls: " + name + " must be 32 bytes")
	}
	var out [32]byte
	copy(out[:], b)
	return out, nil
}

// --- protobuf helpers for Misbehaviour ---

func pbAppendVarint(buf []byte, v uint64) []byte {
	for v >= 0x80 {
		buf = append(buf, byte(v)|0x80)
		v >>= 7
	}
	return append(buf, byte(v))
}

func pbAppendTag(buf []byte, fieldNum, wireType int) []byte {
	return pbAppendVarint(buf, uint64(fieldNum<<3|wireType))
}

func pbAppendMsg(buf []byte, fieldNum int, msg []byte) []byte {
	if len(msg) == 0 {
		return buf
	}
	buf = pbAppendTag(buf, fieldNum, 2)
	buf = pbAppendVarint(buf, uint64(len(msg)))
	return append(buf, msg...)
}

func pbAppendUint64(buf []byte, fieldNum int, v uint64) []byte {
	if v == 0 {
		return buf
	}
	buf = pbAppendTag(buf, fieldNum, 0)
	return pbAppendVarint(buf, v)
}

func pbAppendInt64(buf []byte, fieldNum int, v int64) []byte {
	return pbAppendUint64(buf, fieldNum, uint64(v))
}

func pbAppendInt32(buf []byte, fieldNum int, v int32) []byte {
	return pbAppendUint64(buf, fieldNum, uint64(v))
}

func pbAppendBytes(buf []byte, fieldNum int, data []byte) []byte {
	if len(data) == 0 {
		return buf
	}
	buf = pbAppendTag(buf, fieldNum, 2)
	buf = pbAppendVarint(buf, uint64(len(data)))
	return append(buf, data...)
}

func pbEncodeHeight(h Height) []byte {
	var buf []byte
	buf = pbAppendUint64(buf, 2, h) // ibc-union always uses revision 0; only revision_height (field 2) is emitted
	return buf
}

func pbEncodeHeader(h Header) []byte {
	var buf, lhBuf, tsBuf []byte
	lhBuf = pbAppendInt64(lhBuf, 1, h.SignedHeader.Height)
	tsBuf = pbAppendInt64(tsBuf, 1, h.SignedHeader.TimeSeconds)
	tsBuf = pbAppendInt32(tsBuf, 2, h.SignedHeader.TimeNanos)
	lhBuf = pbAppendMsg(lhBuf, 2, tsBuf)
	lhBuf = pbAppendBytes(lhBuf, 3, h.SignedHeader.ValidatorsHash)
	lhBuf = pbAppendBytes(lhBuf, 4, h.SignedHeader.NextValidatorsHash[:])
	lhBuf = pbAppendBytes(lhBuf, 5, h.SignedHeader.AppHash)
	buf = pbAppendMsg(buf, 1, lhBuf)
	buf = pbAppendMsg(buf, 2, pbEncodeHeight(h.TrustedHeight))
	buf = pbAppendBytes(buf, 3, h.ZeroKnowledgeProof)
	return buf
}

func pbDecodeVarint(buf []byte, pos int) (uint64, int, error) {
	var result uint64
	var shift uint
	for {
		if pos >= len(buf) {
			return 0, pos, errors.New("proto: buffer underflow reading varint")
		}
		b := buf[pos]
		pos++
		result |= uint64(b&0x7F) << shift
		if b&0x80 == 0 {
			return result, pos, nil
		}
		shift += 7
		if shift >= 64 {
			return 0, pos, errors.New("proto: varint overflow")
		}
	}
}

func pbDecodeTag(buf []byte, pos int) (fieldNum, wireType, newPos int, err error) {
	tag, newPos, err := pbDecodeVarint(buf, pos)
	if err != nil {
		return 0, 0, pos, err
	}
	return int(tag >> 3), int(tag & 0x7), newPos, nil
}

func pbDecodeBytes(buf []byte, pos int) ([]byte, int, error) {
	length, pos, err := pbDecodeVarint(buf, pos)
	if err != nil {
		return nil, pos, err
	}
	end := pos + int(length)
	if end > len(buf) {
		return nil, pos, errors.New("proto: buffer underflow reading bytes")
	}
	out := make([]byte, length)
	copy(out, buf[pos:end])
	return out, end, nil
}

func pbSkipField(buf []byte, pos, wireType int) (int, error) {
	switch wireType {
	case 0:
		_, newPos, err := pbDecodeVarint(buf, pos)
		return newPos, err
	case 2:
		_, newPos, err := pbDecodeBytes(buf, pos)
		return newPos, err
	default:
		return pos, errors.New("proto: unsupported wire type")
	}
}

func pbDecodeHeight(buf []byte) (Height, error) {
	var h Height
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return h, err
		}
		switch fieldNum {
		case 1: // revision_number — ibc-union always uses revision 0, skip
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return h, err
			}
		case 2:
			v, newPos, err := pbDecodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h = v
		default:
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return h, err
			}
		}
	}
	return h, nil
}

func pbDecodeTimestamp(buf []byte) (seconds int64, nanos int32, err error) {
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, decErr := pbDecodeTag(buf, pos)
		pos = newPos
		if decErr != nil {
			return 0, 0, decErr
		}
		switch fieldNum {
		case 1:
			v, newPos, decErr := pbDecodeVarint(buf, pos)
			pos = newPos
			if decErr != nil {
				return 0, 0, decErr
			}
			seconds = int64(v)
		case 2:
			v, newPos, decErr := pbDecodeVarint(buf, pos)
			pos = newPos
			if decErr != nil {
				return 0, 0, decErr
			}
			nanos = int32(v)
		default:
			pos, decErr = pbSkipField(buf, pos, wireType)
			if decErr != nil {
				return 0, 0, decErr
			}
		}
	}
	return seconds, nanos, nil
}

func pbDecodeLightHeader(buf []byte) (LightHeader, error) {
	var lh LightHeader
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return lh, err
		}
		switch fieldNum {
		case 1:
			v, newPos, err := pbDecodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.Height = int64(v)
		case 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.TimeSeconds, lh.TimeNanos, err = pbDecodeTimestamp(b)
			if err != nil {
				return lh, err
			}
		case 3:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.ValidatorsHash = b
		case 4:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			if len(b) != 32 {
				return lh, errors.New("cometbls: next validators hash must be 32 bytes")
			}
			copy(lh.NextValidatorsHash[:], b)
		case 5:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.AppHash = b
		default:
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return lh, err
			}
		}
	}
	return lh, nil
}

func pbDecodeHeader(buf []byte) (Header, error) {
	var h Header
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := pbDecodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return h, err
		}
		switch fieldNum {
		case 1:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.SignedHeader, err = pbDecodeLightHeader(b)
			if err != nil {
				return h, err
			}
		case 2:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.TrustedHeight, err = pbDecodeHeight(b)
			if err != nil {
				return h, err
			}
		case 3:
			b, newPos, err := pbDecodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.ZeroKnowledgeProof = b
		default:
			pos, err = pbSkipField(buf, pos, wireType)
			if err != nil {
				return h, err
			}
		}
	}
	return h, nil
}
