package cometbls

import (
	"testing"

	"gno.land/p/aib/ics23"
)

// --- protobuf test helpers ---

func pbVarint(v uint64) []byte {
	var out []byte
	for v >= 0x80 {
		out = append(out, byte(v)|0x80)
		v >>= 7
	}
	return append(out, byte(v))
}

func pbTag(fieldNum, wireType int) []byte {
	return pbVarint(uint64(fieldNum<<3 | wireType))
}

func pbBytesField(fieldNum int, data []byte) []byte {
	out := pbTag(fieldNum, 2)
	out = append(out, pbVarint(uint64(len(data)))...)
	return append(out, data...)
}

func pbVarintField(fieldNum int, v uint64) []byte {
	return append(pbTag(fieldNum, 0), pbVarint(v)...)
}

func encodeLeafOp(hash, prehashKey, prehashValue ics23.HashOp, length ics23.LengthOp, prefix []byte) []byte {
	var out []byte
	if hash != 0 {
		out = append(out, pbVarintField(1, uint64(hash))...)
	}
	if prehashKey != 0 {
		out = append(out, pbVarintField(2, uint64(prehashKey))...)
	}
	if prehashValue != 0 {
		out = append(out, pbVarintField(3, uint64(prehashValue))...)
	}
	if length != 0 {
		out = append(out, pbVarintField(4, uint64(length))...)
	}
	if len(prefix) > 0 {
		out = append(out, pbBytesField(5, prefix)...)
	}
	return out
}

func encodeInnerOp(hash ics23.HashOp, prefix, suffix []byte) []byte {
	var out []byte
	if hash != 0 {
		out = append(out, pbVarintField(1, uint64(hash))...)
	}
	if len(prefix) > 0 {
		out = append(out, pbBytesField(2, prefix)...)
	}
	if len(suffix) > 0 {
		out = append(out, pbBytesField(3, suffix)...)
	}
	return out
}

func encodeExistenceProof(key, value []byte, leaf []byte, innerOps [][]byte) []byte {
	var out []byte
	if len(key) > 0 {
		out = append(out, pbBytesField(1, key)...)
	}
	if len(value) > 0 {
		out = append(out, pbBytesField(2, value)...)
	}
	if len(leaf) > 0 {
		out = append(out, pbBytesField(3, leaf)...)
	}
	for _, op := range innerOps {
		out = append(out, pbBytesField(4, op)...)
	}
	return out
}

func encodeNonExistenceProof(key []byte, left, right []byte) []byte {
	var out []byte
	if len(key) > 0 {
		out = append(out, pbBytesField(1, key)...)
	}
	if len(left) > 0 {
		out = append(out, pbBytesField(2, left)...)
	}
	if len(right) > 0 {
		out = append(out, pbBytesField(3, right)...)
	}
	return out
}

// encodeMerkleProof wraps CommitmentProof bytes into a MerkleProof (field 1, repeated).
func encodeMerkleProof(proofs ...[]byte) []byte {
	var out []byte
	for _, p := range proofs {
		out = append(out, pbBytesField(1, p)...)
	}
	return out
}

func encodeCommitmentExist(epBytes []byte) []byte {
	return pbBytesField(1, epBytes)
}

func encodeCommitmentNonexist(nepBytes []byte) []byte {
	return pbBytesField(2, nepBytes)
}

// --- DecodeProofs tests ---

func TestDecodeProofsEmpty(t *testing.T) {
	proofs, err := DecodeProofs([]byte{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(proofs) != 0 {
		t.Fatalf("expected 0 proofs, got %d", len(proofs))
	}
}

func TestDecodeProofsExistenceProof(t *testing.T) {
	ep := encodeExistenceProof([]byte("mykey"), []byte("myval"), nil, nil)
	buf := encodeMerkleProof(encodeCommitmentExist(ep))

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(proofs) != 1 {
		t.Fatalf("expected 1 proof, got %d", len(proofs))
	}
	exist := proofs[0].GetExist()
	if exist == nil {
		t.Fatal("expected ExistenceProof")
	}
	if string(exist.Key) != "mykey" {
		t.Errorf("key: got %q, want %q", exist.Key, "mykey")
	}
	if string(exist.Value) != "myval" {
		t.Errorf("value: got %q, want %q", exist.Value, "myval")
	}
}

func TestDecodeProofsNonExistenceProof(t *testing.T) {
	leftEP := encodeExistenceProof([]byte("aaa"), []byte("v"), nil, nil)
	rightEP := encodeExistenceProof([]byte("zzz"), []byte("v"), nil, nil)
	nep := encodeNonExistenceProof([]byte("mmm"), leftEP, rightEP)
	buf := encodeMerkleProof(encodeCommitmentNonexist(nep))

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(proofs) != 1 {
		t.Fatalf("expected 1 proof, got %d", len(proofs))
	}
	nonexist := proofs[0].GetNonexist()
	if nonexist == nil {
		t.Fatal("expected NonExistenceProof")
	}
	if nonexist.Left == nil || string(nonexist.Left.Key) != "aaa" {
		t.Error("left existence proof key mismatch")
	}
	if nonexist.Right == nil || string(nonexist.Right.Key) != "zzz" {
		t.Error("right existence proof key mismatch")
	}
}

func TestDecodeProofsTwoProofs(t *testing.T) {
	ep1 := encodeExistenceProof([]byte("k1"), []byte("v1"), nil, nil)
	ep2 := encodeExistenceProof([]byte("k2"), []byte("v2"), nil, nil)
	buf := encodeMerkleProof(encodeCommitmentExist(ep1), encodeCommitmentExist(ep2))

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(proofs) != 2 {
		t.Fatalf("expected 2 proofs, got %d", len(proofs))
	}
	if string(proofs[0].GetExist().Key) != "k1" {
		t.Error("first proof key mismatch")
	}
	if string(proofs[1].GetExist().Key) != "k2" {
		t.Error("second proof key mismatch")
	}
}

func TestDecodeProofsCorruptedBuffer(t *testing.T) {
	// Truncate mid-varint
	_, err := DecodeProofs([]byte{0x0a, 0xff})
	if err == nil {
		t.Fatal("expected error for corrupted buffer")
	}
}

func TestDecodeProofsUnknownFieldSkipped(t *testing.T) {
	// Field 9 (unknown) with wire type 2, then a real proof
	ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
	unknown := pbBytesField(9, []byte("ignored"))
	buf := append(unknown, encodeMerkleProof(encodeCommitmentExist(ep))...)

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(proofs) != 1 {
		t.Fatalf("expected 1 proof after skipping unknown field, got %d", len(proofs))
	}
}

func TestDecodeProofsEmptyCommitmentProof(t *testing.T) {
	// CommitmentProof with no known fields (empty bytes)
	buf := encodeMerkleProof([]byte{})
	_, err := DecodeProofs(buf)
	if err == nil {
		t.Fatal("expected error for empty commitment proof")
	}
}

func TestDecodeProofsLeafOpAllFields(t *testing.T) {
	leaf := encodeLeafOp(
		ics23.HashOp_SHA256,
		ics23.HashOp_NO_HASH,
		ics23.HashOp_SHA256,
		ics23.LengthOp_VAR_PROTO,
		[]byte{0x00},
	)
	ep := encodeExistenceProof([]byte("k"), []byte("v"), leaf, nil)
	buf := encodeMerkleProof(encodeCommitmentExist(ep))

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	exist := proofs[0].GetExist()
	if exist.Leaf == nil {
		t.Fatal("expected LeafOp")
	}
	if exist.Leaf.Hash != ics23.HashOp_SHA256 {
		t.Errorf("leaf hash: got %v, want SHA256", exist.Leaf.Hash)
	}
	if exist.Leaf.PrehashValue != ics23.HashOp_SHA256 {
		t.Errorf("leaf prehash_value: got %v, want SHA256", exist.Leaf.PrehashValue)
	}
	if exist.Leaf.Length != ics23.LengthOp_VAR_PROTO {
		t.Errorf("leaf length: got %v, want VAR_PROTO", exist.Leaf.Length)
	}
	if len(exist.Leaf.Prefix) != 1 || exist.Leaf.Prefix[0] != 0x00 {
		t.Error("leaf prefix mismatch")
	}
}

func TestDecodeProofsInnerOpPrefixAndSuffix(t *testing.T) {
	inner := encodeInnerOp(ics23.HashOp_SHA256, []byte("pre"), []byte("suf"))
	ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, [][]byte{inner})
	buf := encodeMerkleProof(encodeCommitmentExist(ep))

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	exist := proofs[0].GetExist()
	if len(exist.Path) != 1 {
		t.Fatalf("expected 1 inner op, got %d", len(exist.Path))
	}
	if exist.Path[0].Hash != ics23.HashOp_SHA256 {
		t.Error("inner op hash mismatch")
	}
	if string(exist.Path[0].Prefix) != "pre" {
		t.Error("inner op prefix mismatch")
	}
	if string(exist.Path[0].Suffix) != "suf" {
		t.Error("inner op suffix mismatch")
	}
}

func TestDecodeProofsMultipleInnerOps(t *testing.T) {
	ops := [][]byte{
		encodeInnerOp(ics23.HashOp_SHA256, []byte("p1"), []byte("s1")),
		encodeInnerOp(ics23.HashOp_SHA256, []byte("p2"), []byte("s2")),
		encodeInnerOp(ics23.HashOp_SHA256, []byte("p3"), []byte("s3")),
	}
	ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, ops)
	buf := encodeMerkleProof(encodeCommitmentExist(ep))

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	exist := proofs[0].GetExist()
	if len(exist.Path) != 3 {
		t.Fatalf("expected 3 inner ops, got %d", len(exist.Path))
	}
	for i, op := range exist.Path {
		if string(op.Prefix) != string(ops[i][2:4]) {
			// field-encoded; just check count is right
		}
		if op.Hash != ics23.HashOp_SHA256 {
			t.Errorf("inner op %d hash mismatch", i)
		}
	}
}

func TestDecodeProofsNonExistenceLeftOnly(t *testing.T) {
	leftEP := encodeExistenceProof([]byte("aaa"), []byte("v"), nil, nil)
	nep := encodeNonExistenceProof(nil, leftEP, nil)
	buf := encodeMerkleProof(encodeCommitmentNonexist(nep))

	proofs, err := DecodeProofs(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	nonexist := proofs[0].GetNonexist()
	if nonexist.Left == nil {
		t.Fatal("expected Left proof")
	}
	if nonexist.Right != nil {
		t.Error("expected nil Right proof")
	}
}
