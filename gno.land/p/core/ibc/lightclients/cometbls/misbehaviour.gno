package cometbls

import "errors"

// Misbehaviour is protobuf encoded.
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
