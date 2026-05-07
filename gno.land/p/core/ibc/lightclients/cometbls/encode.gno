package cometbls

// appendVarint appends v as a protobuf varint to buf.
func appendVarint(buf []byte, v uint64) []byte {
	for v >= 0x80 {
		buf = append(buf, byte(v)|0x80)
		v >>= 7
	}
	return append(buf, byte(v))
}

// appendTag appends (fieldNum << 3) | wireType as a varint.
func appendTag(buf []byte, fieldNum, wireType int) []byte {
	return appendVarint(buf, uint64(fieldNum<<3|wireType))
}

// appendUint64Field appends a varint field. Skips the field if v == 0 (proto3).
func appendUint64Field(buf []byte, fieldNum int, v uint64) []byte {
	if v == 0 {
		return buf
	}
	buf = appendTag(buf, fieldNum, wireVarint)
	return appendVarint(buf, v)
}

// appendInt64Field appends an int64 as a varint field.
func appendInt64Field(buf []byte, fieldNum int, v int64) []byte {
	return appendUint64Field(buf, fieldNum, uint64(v))
}

// appendInt32Field appends an int32 as a varint field.
func appendInt32Field(buf []byte, fieldNum int, v int32) []byte {
	return appendUint64Field(buf, fieldNum, uint64(v))
}

// appendBytesField appends a length-delimited field. Skips if data is empty (proto3).
func appendBytesField(buf []byte, fieldNum int, data []byte) []byte {
	if len(data) == 0 {
		return buf
	}
	buf = appendTag(buf, fieldNum, wireLen)
	buf = appendVarint(buf, uint64(len(data)))
	return append(buf, data...)
}

// appendStringField appends a string as a length-delimited field.
func appendStringField(buf []byte, fieldNum int, s string) []byte {
	return appendBytesField(buf, fieldNum, []byte(s))
}

// appendMessageField appends an embedded message field. Skips if msg is empty (proto3).
func appendMessageField(buf []byte, fieldNum int, msg []byte) []byte {
	return appendBytesField(buf, fieldNum, msg)
}

// EncodeHeight encodes an ibc.core.client.v1.Height message.
// ibc-union always uses revision_number=0; only revision_height (field 2) is emitted.
func EncodeHeight(h Height) []byte {
	var buf []byte
	buf = appendUint64Field(buf, 2, h)
	return buf
}

// EncodeMerkleRoot encodes an ibc.core.commitment.v1.MerkleRoot message.
func EncodeMerkleRoot(mr MerkleRoot) []byte {
	var buf []byte
	buf = appendBytesField(buf, 1, mr.Hash)
	return buf
}

// EncodeClientState encodes a union.ibc.lightclients.cometbls.v1.ClientState.
func EncodeClientState(cs ClientState) []byte {
	var buf []byte
	buf = appendStringField(buf, 1, cs.ChainID)
	buf = appendUint64Field(buf, 2, cs.TrustingPeriod)
	buf = appendUint64Field(buf, 4, cs.MaxClockDrift) // field 3 is reserved/deleted
	buf = appendMessageField(buf, 5, EncodeHeight(cs.FrozenHeight))
	buf = appendMessageField(buf, 6, EncodeHeight(cs.LatestHeight))
	return buf
}

// EncodeConsensusState encodes a union.ibc.lightclients.cometbls.v1.ConsensusState.
func EncodeConsensusState(cs ConsensusState) []byte {
	var buf []byte
	buf = appendUint64Field(buf, 1, cs.Timestamp)
	buf = appendMessageField(buf, 2, EncodeMerkleRoot(cs.Root))
	buf = appendBytesField(buf, 3, cs.NextValidatorsHash)
	return buf
}

// EncodeLightHeader encodes a union.ibc.lightclients.cometbls.v1.LightHeader.
func EncodeLightHeader(lh LightHeader) []byte {
	var buf []byte
	buf = appendInt64Field(buf, 1, lh.Height)
	var tsBuf []byte
	tsBuf = appendInt64Field(tsBuf, 1, lh.TimeSeconds)
	tsBuf = appendInt32Field(tsBuf, 2, lh.TimeNanos)
	buf = appendMessageField(buf, 2, tsBuf)
	buf = appendBytesField(buf, 3, lh.ValidatorsHash)
	buf = appendBytesField(buf, 4, lh.NextValidatorsHash)
	buf = appendBytesField(buf, 5, lh.AppHash)
	return buf
}

// EncodeHeader encodes a union.ibc.lightclients.cometbls.v1.Header.
func EncodeHeader(h Header) []byte {
	var buf []byte
	buf = appendMessageField(buf, 1, EncodeLightHeader(h.SignedHeader))
	buf = appendMessageField(buf, 2, EncodeHeight(h.TrustedHeight))
	buf = appendBytesField(buf, 3, h.ZeroKnowledgeProof)
	return buf
}

// EncodeMisbehaviour encodes a union.ibc.lightclients.cometbls.v1.Misbehaviour.
func EncodeMisbehaviour(m Misbehaviour) []byte {
	var buf []byte
	buf = appendMessageField(buf, 1, EncodeHeader(m.HeaderA))
	buf = appendMessageField(buf, 2, EncodeHeader(m.HeaderB))
	return buf
}
