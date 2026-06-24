package cometbls

import (
	"gno.land/p/aib/encoding/proto"
	"gno.land/p/aib/ics23"
)

// ICS23 proof wire encoders, built on the shared proto append helpers. They emit
// exactly the shape cometbls DecodeProofs consumes: a MerkleProof (repeated
// field 1) of CommitmentProofs, each holding an ExistenceProof (field 1) with a
// LeafOp (field 3). Fields at the proto3 default (0 / empty) are omitted, which
// AppendVarint/AppendLengthDelimited handle and the decoder fills back in.

func encodeLeafOp(op *ics23.LeafOp) []byte {
	var out []byte
	if op.Hash != 0 {
		out = proto.AppendVarint(out, 1, uint64(op.Hash))
	}
	if op.PrehashKey != 0 {
		out = proto.AppendVarint(out, 2, uint64(op.PrehashKey))
	}
	if op.PrehashValue != 0 {
		out = proto.AppendVarint(out, 3, uint64(op.PrehashValue))
	}
	if op.Length != 0 {
		out = proto.AppendVarint(out, 4, uint64(op.Length))
	}

	return proto.AppendLengthDelimited(out, 5, op.Prefix)
}

func encodeExistenceProof(key, value, leaf []byte, innerOps [][]byte) []byte {
	out := proto.AppendLengthDelimited(nil, 1, key)
	out = proto.AppendLengthDelimited(out, 2, value)
	out = proto.AppendLengthDelimited(out, 3, leaf)
	for _, op := range innerOps {
		out = proto.AppendLengthDelimited(out, 4, op)
	}

	return out
}

// encodeCommitmentExist wraps existence-proof bytes as a CommitmentProof (exist
// = field 1).
func encodeCommitmentExist(epBytes []byte) []byte {
	return proto.AppendLengthDelimited(nil, 1, epBytes)
}

// encodeMerkleProof wraps CommitmentProof bytes into a MerkleProof (repeated
// field 1).
func encodeMerkleProof(proofs ...[]byte) []byte {
	var out []byte
	for _, p := range proofs {
		out = proto.AppendLengthDelimited(out, 1, p)
	}

	return out
}
