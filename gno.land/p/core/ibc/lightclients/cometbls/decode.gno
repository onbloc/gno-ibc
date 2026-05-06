package cometbls

import "errors"

// Proto wire types
const (
	wireVarint = 0
	wireLen    = 2
)

// decodeTag reads a proto field tag and returns field number, wire type, and
// the new position. Tags are encoded as (field_number << 3) | wire_type.
func decodeTag(buf []byte, pos int) (fieldNum, wireType, newPos int, err error) {
	tag, newPos, err := decodeVarint(buf, pos)
	if err != nil {
		return 0, 0, pos, err
	}
	return int(tag >> 3), int(tag & 0x7), newPos, nil
}

// decodeVarint reads a protobuf varint from buf starting at pos.
func decodeVarint(buf []byte, pos int) (uint64, int, error) {
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

// decodeBytes reads a length-delimited field (string, bytes, embedded message).
func decodeBytes(buf []byte, pos int) ([]byte, int, error) {
	length, pos, err := decodeVarint(buf, pos)
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

// skipField advances pos past a field of the given wire type.
func skipField(buf []byte, pos, wireType int) (int, error) {
	switch wireType {
	case wireVarint:
		_, newPos, err := decodeVarint(buf, pos)
		return newPos, err
	case wireLen:
		_, newPos, err := decodeBytes(buf, pos)
		return newPos, err
	default:
		return pos, errors.New("proto: unsupported wire type")
	}
}

// DecodeHeight decodes an ibc.core.client.v1.Height message.
func DecodeHeight(buf []byte) (Height, error) {
	var h Height
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := decodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return h, err
		}
		switch fieldNum {
		case 1: // revision_number (uint64)
			v, newPos, err := decodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.RevisionNumber = v
		case 2: // revision_height (uint64)
			v, newPos, err := decodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.RevisionHeight = v
		default:
			pos, err = skipField(buf, pos, wireType)
			if err != nil {
				return h, err
			}
		}
	}
	return h, nil
}

// DecodeMerkleRoot decodes an ibc.core.commitment.v1.MerkleRoot message.
func DecodeMerkleRoot(buf []byte) (MerkleRoot, error) {
	var mr MerkleRoot
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := decodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return mr, err
		}
		switch fieldNum {
		case 1: // hash (bytes)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return mr, err
			}
			mr.Hash = b
		default:
			pos, err = skipField(buf, pos, wireType)
			if err != nil {
				return mr, err
			}
		}
	}
	return mr, nil
}

// decodeTimestamp decodes a google.protobuf.Timestamp embedded message and
// returns (seconds, nanos).
func decodeTimestamp(buf []byte) (seconds int64, nanos int32, err error) {
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, decErr := decodeTag(buf, pos)
		pos = newPos
		if decErr != nil {
			return 0, 0, decErr
		}
		switch fieldNum {
		case 1: // seconds (int64)
			v, newPos, decErr := decodeVarint(buf, pos)
			pos = newPos
			if decErr != nil {
				return 0, 0, decErr
			}
			seconds = int64(v)
		case 2: // nanos (int32)
			v, newPos, decErr := decodeVarint(buf, pos)
			pos = newPos
			if decErr != nil {
				return 0, 0, decErr
			}
			nanos = int32(v)
		default:
			pos, decErr = skipField(buf, pos, wireType)
			if decErr != nil {
				return 0, 0, decErr
			}
		}
	}
	return seconds, nanos, nil
}

// DecodeClientState decodes a union.ibc.lightclients.cometbls.v1.ClientState.
func DecodeClientState(buf []byte) (ClientState, error) {
	var cs ClientState
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := decodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return cs, err
		}
		switch fieldNum {
		case 1: // chain_id (string)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.ChainID = string(b)
		case 2: // trusting_period (uint64)
			v, newPos, err := decodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.TrustingPeriod = v
		case 4: // max_clock_drift (uint64, field 3 is reserved/deleted)
			v, newPos, err := decodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.MaxClockDrift = v
		case 5: // frozen_height (Height)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.FrozenHeight, err = DecodeHeight(b)
			if err != nil {
				return cs, err
			}
		case 6: // latest_height (Height)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.LatestHeight, err = DecodeHeight(b)
			if err != nil {
				return cs, err
			}
		default:
			pos, err = skipField(buf, pos, wireType)
			if err != nil {
				return cs, err
			}
		}
	}
	return cs, nil
}

// DecodeConsensusState decodes a union.ibc.lightclients.cometbls.v1.ConsensusState.
func DecodeConsensusState(buf []byte) (ConsensusState, error) {
	var cs ConsensusState
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := decodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return cs, err
		}
		switch fieldNum {
		case 1: // timestamp (uint64, nanoseconds)
			v, newPos, err := decodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.Timestamp = v
		case 2: // root (MerkleRoot)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.Root, err = DecodeMerkleRoot(b)
			if err != nil {
				return cs, err
			}
		case 3: // next_validators_hash (bytes)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return cs, err
			}
			cs.NextValidatorsHash = b
		default:
			pos, err = skipField(buf, pos, wireType)
			if err != nil {
				return cs, err
			}
		}
	}
	return cs, nil
}

// DecodeLightHeader decodes a union.ibc.lightclients.cometbls.v1.LightHeader.
func DecodeLightHeader(buf []byte) (LightHeader, error) {
	var lh LightHeader
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := decodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return lh, err
		}
		switch fieldNum {
		case 1: // height (int64)
			v, newPos, err := decodeVarint(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.Height = int64(v)
		case 2: // time (google.protobuf.Timestamp)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.TimeSeconds, lh.TimeNanos, err = decodeTimestamp(b)
			if err != nil {
				return lh, err
			}
		case 3: // validators_hash (bytes)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.ValidatorsHash = b
		case 4: // next_validators_hash (bytes)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.NextValidatorsHash = b
		case 5: // app_hash (bytes)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return lh, err
			}
			lh.AppHash = b
		default:
			pos, err = skipField(buf, pos, wireType)
			if err != nil {
				return lh, err
			}
		}
	}
	return lh, nil
}

// DecodeHeader decodes a union.ibc.lightclients.cometbls.v1.Header.
func DecodeHeader(buf []byte) (Header, error) {
	var h Header
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := decodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return h, err
		}
		switch fieldNum {
		case 1: // signed_header (LightHeader)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.SignedHeader, err = DecodeLightHeader(b)
			if err != nil {
				return h, err
			}
		case 2: // trusted_height (Height)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.TrustedHeight, err = DecodeHeight(b)
			if err != nil {
				return h, err
			}
		case 3: // zero_knowledge_proof (bytes)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return h, err
			}
			h.ZeroKnowledgeProof = b
		default:
			pos, err = skipField(buf, pos, wireType)
			if err != nil {
				return h, err
			}
		}
	}
	return h, nil
}

// DecodeMisbehaviour decodes a union.ibc.lightclients.cometbls.v1.Misbehaviour.
func DecodeMisbehaviour(buf []byte) (Misbehaviour, error) {
	var m Misbehaviour
	pos := 0
	for pos < len(buf) {
		fieldNum, wireType, newPos, err := decodeTag(buf, pos)
		pos = newPos
		if err != nil {
			return m, err
		}
		switch fieldNum {
		case 1: // header_a (Header)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return m, err
			}
			m.HeaderA, err = DecodeHeader(b)
			if err != nil {
				return m, err
			}
		case 2: // header_b (Header)
			b, newPos, err := decodeBytes(buf, pos)
			pos = newPos
			if err != nil {
				return m, err
			}
			m.HeaderB, err = DecodeHeader(b)
			if err != nil {
				return m, err
			}
		default:
			pos, err = skipField(buf, pos, wireType)
			if err != nil {
				return m, err
			}
		}
	}
	return m, nil
}
