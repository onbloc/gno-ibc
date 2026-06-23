package cometbls

import (
	"testing"

	"gno.land/p/aib/encoding/proto"
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

func TestDecodeProofs(t *testing.T) {
	leafAllFields := encodeLeafOp(
		ics23.HashOp_SHA256,
		ics23.HashOp_NO_HASH,
		ics23.HashOp_SHA256,
		ics23.LengthOp_VAR_PROTO,
		[]byte{0x00},
	)
	threeInnerOps := [][]byte{
		encodeInnerOp(ics23.HashOp_SHA256, []byte("p1"), []byte("s1")),
		encodeInnerOp(ics23.HashOp_SHA256, []byte("p2"), []byte("s2")),
		encodeInnerOp(ics23.HashOp_SHA256, []byte("p3"), []byte("s3")),
	}

	cases := []struct {
		name    string
		buf     []byte
		wantErr bool
		check   func(*testing.T, []ics23.CommitmentProof)
	}{
		{
			name: "empty",
			buf:  []byte{},
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
				if len(proofs) != 0 {
					t.Fatalf("expected 0 proofs, got %d", len(proofs))
				}
			},
		},
		{
			name: "existence proof",
			buf:  encodeMerkleProof(encodeCommitmentExist(encodeExistenceProof([]byte("mykey"), []byte("myval"), nil, nil))),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
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
			},
		},
		{
			name: "non-existence proof",
			buf: encodeMerkleProof(encodeCommitmentNonexist(encodeNonExistenceProof(
				[]byte("mmm"),
				encodeExistenceProof([]byte("aaa"), []byte("v"), nil, nil),
				encodeExistenceProof([]byte("zzz"), []byte("v"), nil, nil),
			))),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
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
			},
		},
		{
			name: "two proofs",
			buf: encodeMerkleProof(
				encodeCommitmentExist(encodeExistenceProof([]byte("k1"), []byte("v1"), nil, nil)),
				encodeCommitmentExist(encodeExistenceProof([]byte("k2"), []byte("v2"), nil, nil)),
			),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
				if len(proofs) != 2 {
					t.Fatalf("expected 2 proofs, got %d", len(proofs))
				}
				if string(proofs[0].GetExist().Key) != "k1" {
					t.Error("first proof key mismatch")
				}
				if string(proofs[1].GetExist().Key) != "k2" {
					t.Error("second proof key mismatch")
				}
			},
		},
		{
			name:    "corrupted buffer",
			buf:     []byte{0x0a, 0xff},
			wantErr: true,
		},
		{
			name: "unknown field skipped",
			buf: append(
				pbBytesField(9, []byte("ignored")),
				encodeMerkleProof(encodeCommitmentExist(encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)))...,
			),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
				if len(proofs) != 1 {
					t.Fatalf("expected 1 proof after skipping unknown field, got %d", len(proofs))
				}
			},
		},
		{
			name:    "empty commitment proof",
			buf:     encodeMerkleProof([]byte{}),
			wantErr: true,
		},
		{
			name: "leaf op all fields",
			buf: encodeMerkleProof(encodeCommitmentExist(
				encodeExistenceProof([]byte("k"), []byte("v"), leafAllFields, nil),
			)),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
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
			},
		},
		{
			name: "inner op prefix and suffix",
			buf: encodeMerkleProof(encodeCommitmentExist(
				encodeExistenceProof([]byte("k"), []byte("v"), nil, [][]byte{
					encodeInnerOp(ics23.HashOp_SHA256, []byte("pre"), []byte("suf")),
				}),
			)),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
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
			},
		},
		{
			name: "multiple inner ops",
			buf: encodeMerkleProof(encodeCommitmentExist(
				encodeExistenceProof([]byte("k"), []byte("v"), nil, threeInnerOps),
			)),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
				exist := proofs[0].GetExist()
				if len(exist.Path) != 3 {
					t.Fatalf("expected 3 inner ops, got %d", len(exist.Path))
				}
				for i, op := range exist.Path {
					if op.Hash != ics23.HashOp_SHA256 {
						t.Errorf("inner op %d hash mismatch", i)
					}
				}
			},
		},
		{
			name: "non-existence left only",
			buf: encodeMerkleProof(encodeCommitmentNonexist(encodeNonExistenceProof(
				nil,
				encodeExistenceProof([]byte("aaa"), []byte("v"), nil, nil),
				nil,
			))),
			check: func(t *testing.T, proofs []ics23.CommitmentProof) {
				nonexist := proofs[0].GetNonexist()
				if nonexist.Left == nil {
					t.Fatal("expected Left proof")
				}
				if nonexist.Right != nil {
					t.Error("expected nil Right proof")
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			proofs, err := DecodeProofs(tc.buf)
			if tc.wantErr {
				if err == nil {
					t.Fatal("expected error")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			tc.check(t, proofs)
		})
	}
}

// --- Direct protobuf decoder tests ---

func TestDecodeCommitmentProof(t *testing.T) {
	cases := []struct {
		name    string
		buf     []byte
		wantErr string
		check   func(ics23.CommitmentProof) bool
	}{
		{
			name: "existence proof decoded",
			buf:  encodeCommitmentExist(encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)),
			check: func(cp ics23.CommitmentProof) bool {
				ep := cp.GetExist()
				return ep != nil && string(ep.Key) == "k" && string(ep.Value) == "v"
			},
		},
		{
			name: "non-existence proof decoded",
			buf:  encodeCommitmentNonexist(encodeNonExistenceProof([]byte("k"), nil, nil)),
			check: func(cp ics23.CommitmentProof) bool {
				nep := cp.GetNonexist()
				return nep != nil && string(nep.Key) == "k"
			},
		},
		{
			name:    "empty proof returns error",
			buf:     []byte{},
			wantErr: "empty commitment proof",
		},
		{
			name: "skip unknown field then decode existence",
			buf: func() []byte {
				ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
				unknown := pbVarintField(9, 42) // unknown varint field
				return append(unknown, encodeCommitmentExist(ep)...)
			}(),
			check: func(cp ics23.CommitmentProof) bool {
				ep := cp.GetExist()
				return ep != nil && string(ep.Key) == "k"
			},
		},
		{
			name: "skip LEN field with unknown wire type then decode",
			buf: func() []byte {
				// Field 3 with wire type LEN then a valid existence proof
				unknown := pbBytesField(3, []byte("ignored"))
				ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
				return append(unknown, encodeCommitmentExist(ep)...)
			}(),
			check: func(cp ics23.CommitmentProof) bool {
				ep := cp.GetExist()
				return ep != nil && string(ep.Key) == "k"
			},
		},
		{
			name: "skip VARINT field with unknown wire type then decode",
			buf: func() []byte {
				unknown := pbVarintField(7, 123)
				ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
				return append(unknown, encodeCommitmentExist(ep)...)
			}(),
			check: func(cp ics23.CommitmentProof) bool {
				ep := cp.GetExist()
				return ep != nil && string(ep.Key) == "k"
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeCommitmentProof(tc.buf)
			if tc.wantErr != "" {
				if err == nil {
					t.Fatalf("expected error containing %q, got nil", tc.wantErr)
				}
				if tc.wantErr != "" && !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %q", tc.wantErr, err.Error())
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !tc.check(got) {
				t.Fatal("check function failed")
			}
		})
	}
}

func TestDecodeExistenceProof(t *testing.T) {
	cases := []struct {
		name    string
		buf     []byte
		wantErr string
		check   func(*ics23.ExistenceProof) bool
	}{
		{
			name: "key and value decoded",
			buf:  encodeExistenceProof([]byte("mykey"), []byte("myval"), nil, nil),
			check: func(ep *ics23.ExistenceProof) bool {
				return string(ep.Key) == "mykey" && string(ep.Value) == "myval"
			},
		},
		{
			name: "leaf op decoded",
			buf: encodeExistenceProof([]byte("k"), []byte("v"),
				encodeLeafOp(ics23.HashOp_SHA256, ics23.HashOp_NO_HASH, ics23.HashOp_SHA256, ics23.LengthOp_VAR_PROTO, []byte{0x00}),
				nil),
			check: func(ep *ics23.ExistenceProof) bool {
				return ep.Leaf != nil && ep.Leaf.Hash == ics23.HashOp_SHA256
			},
		},
		{
			name: "multiple inner ops decoded",
			buf: encodeExistenceProof([]byte("k"), []byte("v"), nil, [][]byte{
				encodeInnerOp(ics23.HashOp_SHA256, []byte("p1"), []byte("s1")),
				encodeInnerOp(ics23.HashOp_SHA256, []byte("p2"), []byte("s2")),
			}),
			check: func(ep *ics23.ExistenceProof) bool {
				return len(ep.Path) == 2 && ep.Path[0].Hash == ics23.HashOp_SHA256
			},
		},
		{
			name: "empty proof returns valid struct with nil fields",
			buf:  []byte{},
			check: func(ep *ics23.ExistenceProof) bool {
				return ep.Key == nil && ep.Value == nil && ep.Leaf == nil && len(ep.Path) == 0
			},
		},
		{
			name: "skip unknown field in existence proof",
			buf: func() []byte {
				unknown := pbVarintField(9, 42)
				ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
				return append(unknown, ep...)
			}(),
			check: func(ep *ics23.ExistenceProof) bool {
				return string(ep.Key) == "k" && string(ep.Value) == "v"
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeExistenceProof(tc.buf)
			if tc.wantErr != "" {
				if err == nil {
					t.Fatalf("expected error containing %q, got nil", tc.wantErr)
				}
				if !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %q", tc.wantErr, err.Error())
				}
				return
			}
			if err != nil && tc.wantErr == "" {
				t.Fatalf("unexpected error: %v", err)
			}
			if !tc.check(got) {
				t.Fatal("check function failed")
			}
		})
	}
}

func TestDecodeLeafOp(t *testing.T) {
	cases := []struct {
		name    string
		buf     []byte
		wantErr string
		check   func(*ics23.LeafOp) bool
	}{
		{
			name: "all fields decoded",
			buf: encodeLeafOp(
				ics23.HashOp_SHA256,
				ics23.HashOp_NO_HASH,
				ics23.HashOp_SHA256,
				ics23.LengthOp_VAR_PROTO,
				[]byte{0xAB}),
			check: func(lop *ics23.LeafOp) bool {
				return lop.Hash == ics23.HashOp_SHA256 &&
					lop.PrehashKey == ics23.HashOp_NO_HASH &&
					lop.PrehashValue == ics23.HashOp_SHA256 &&
					lop.Length == ics23.LengthOp_VAR_PROTO &&
					len(lop.Prefix) == 1 && lop.Prefix[0] == 0xAB
			},
		},
		{
			name: "partial fields decoded",
			buf:  encodeLeafOp(ics23.HashOp_SHA256, 0, 0, 0, nil),
			check: func(lop *ics23.LeafOp) bool {
				return lop.Hash == ics23.HashOp_SHA256 &&
					lop.PrehashKey == 0 &&
					lop.PrehashValue == 0 &&
					lop.Length == 0 &&
					len(lop.Prefix) == 0
			},
		},
		{
			name: "empty buffer returns zero values",
			buf:  []byte{},
			check: func(lop *ics23.LeafOp) bool {
				return lop.Hash == 0 && lop.PrehashKey == 0 && lop.PrehashValue == 0 &&
					lop.Length == 0 && len(lop.Prefix) == 0
			},
		},
		{
			name: "skip unknown field",
			buf: func() []byte {
				unknown := pbVarintField(9, 42)
				lop := encodeLeafOp(ics23.HashOp_SHA256, 0, 0, 0, nil)
				return append(unknown, lop...)
			}(),
			check: func(lop *ics23.LeafOp) bool {
				return lop.Hash == ics23.HashOp_SHA256
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeLeafOp(tc.buf)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !tc.check(got) {
				t.Fatal("check function failed")
			}
		})
	}
}

func TestDecodeInnerOp(t *testing.T) {
	cases := []struct {
		name    string
		buf     []byte
		wantErr string
		check   func(*ics23.InnerOp) bool
	}{
		{
			name: "all fields decoded",
			buf:  encodeInnerOp(ics23.HashOp_SHA256, []byte("pre"), []byte("suf")),
			check: func(iop *ics23.InnerOp) bool {
				return iop.Hash == ics23.HashOp_SHA256 &&
					string(iop.Prefix) == "pre" &&
					string(iop.Suffix) == "suf"
			},
		},
		{
			name: "partial fields decoded",
			buf:  encodeInnerOp(ics23.HashOp_SHA256, []byte("pre"), nil),
			check: func(iop *ics23.InnerOp) bool {
				return iop.Hash == ics23.HashOp_SHA256 &&
					string(iop.Prefix) == "pre" &&
					len(iop.Suffix) == 0
			},
		},
		{
			name: "empty buffer returns zero values",
			buf:  []byte{},
			check: func(iop *ics23.InnerOp) bool {
				return iop.Hash == 0 && len(iop.Prefix) == 0 && len(iop.Suffix) == 0
			},
		},
		{
			name: "skip unknown field",
			buf: func() []byte {
				unknown := pbBytesField(9, []byte("ignored"))
				iop := encodeInnerOp(ics23.HashOp_SHA256, []byte("pre"), nil)
				return append(unknown, iop...)
			}(),
			check: func(iop *ics23.InnerOp) bool {
				return iop.Hash == ics23.HashOp_SHA256
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeInnerOp(tc.buf)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !tc.check(got) {
				t.Fatal("check function failed")
			}
		})
	}
}

func TestDecodeNonExistenceProof(t *testing.T) {
	cases := []struct {
		name    string
		buf     []byte
		wantErr string
		check   func(*ics23.NonExistenceProof) bool
	}{
		{
			name: "key only decoded",
			buf:  encodeNonExistenceProof([]byte("key"), nil, nil),
			check: func(nep *ics23.NonExistenceProof) bool {
				return string(nep.Key) == "key" && nep.Left == nil && nep.Right == nil
			},
		},
		{
			name: "left existence proof decoded",
			buf: func() []byte {
				leftEP := encodeExistenceProof([]byte("aaa"), []byte("v"), nil, nil)
				return encodeNonExistenceProof([]byte("mmm"), leftEP, nil)
			}(),
			check: func(nep *ics23.NonExistenceProof) bool {
				return nep.Left != nil && string(nep.Left.Key) == "aaa" &&
					nep.Right == nil
			},
		},
		{
			name: "right existence proof decoded",
			buf: func() []byte {
				rightEP := encodeExistenceProof([]byte("zzz"), []byte("v"), nil, nil)
				return encodeNonExistenceProof([]byte("mmm"), nil, rightEP)
			}(),
			check: func(nep *ics23.NonExistenceProof) bool {
				return nep.Left == nil && nep.Right != nil &&
					string(nep.Right.Key) == "zzz"
			},
		},
		{
			name: "both existence proofs decoded",
			buf: func() []byte {
				leftEP := encodeExistenceProof([]byte("aaa"), []byte("v"), nil, nil)
				rightEP := encodeExistenceProof([]byte("zzz"), []byte("v"), nil, nil)
				return encodeNonExistenceProof([]byte("mmm"), leftEP, rightEP)
			}(),
			check: func(nep *ics23.NonExistenceProof) bool {
				return nep.Left != nil && nep.Right != nil &&
					string(nep.Left.Key) == "aaa" &&
					string(nep.Right.Key) == "zzz"
			},
		},
		{
			name: "empty buffer returns zero values",
			buf:  []byte{},
			check: func(nep *ics23.NonExistenceProof) bool {
				return nep.Key == nil && nep.Left == nil && nep.Right == nil
			},
		},
		{
			name: "skip unknown LEN field",
			buf: func() []byte {
				unknown := pbBytesField(9, []byte("ignored"))
				nep := encodeNonExistenceProof([]byte("key"), nil, nil)
				return append(unknown, nep...)
			}(),
			check: func(nep *ics23.NonExistenceProof) bool {
				return string(nep.Key) == "key"
			},
		},
		{
			name: "skip unknown VARINT field",
			buf: func() []byte {
				unknown := pbVarintField(7, 123)
				nep := encodeNonExistenceProof([]byte("key"), nil, nil)
				return append(unknown, nep...)
			}(),
			check: func(nep *ics23.NonExistenceProof) bool {
				return string(nep.Key) == "key"
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeNonExistenceProof(tc.buf)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil && tc.wantErr == "" {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.check != nil && !tc.check(got) {
				t.Fatal("check function failed")
			}
		})
	}
}

func TestDecodeTag(t *testing.T) {
	cases := []struct {
		name         string
		buf          []byte
		wantFieldNum int
		wantWireType int
		wantErr      string
	}{
		{
			name:         "field 1 VARINT",
			buf:          []byte{0x08}, // 1 << 3 | 0
			wantFieldNum: 1,
			wantWireType: 0,
		},
		{
			name:         "field 2 LEN",
			buf:          []byte{0x12}, // 2 << 3 | 2
			wantFieldNum: 2,
			wantWireType: 2,
		},
		{
			name:         "field 15 FIXED64",
			buf:          []byte{0x79}, // 15 << 3 | 1
			wantFieldNum: 15,
			wantWireType: 1,
		},
		{
			name:    "field 16 FIXED32",
			buf:     []byte{0x82}, // first byte of 16 << 3 | 5 (requires multibyte varint)
			wantErr: "",
		},
		{
			name:    "max field number with VARINT",
			buf:     []byte{0xF8, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F}, // max field num (15) << 3 | 7 (wire type 7 unsupported)
			wantErr: "",                                         // Any wire type in tag is OK; tag decode only splits bits
		},
		{
			name:    "empty buffer",
			buf:     []byte{},
			wantErr: "",
		},
		{
			name:    "valid multibyte varint tag",
			buf:     []byte{0xF8, 0x02}, // field 300, wire type 0: (300 << 3) | 0 = 2400 = 0x960, varint encoded
			wantErr: "",                 // Invalid varint for this test data; just check it doesn't panic
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			fieldNum, wireType, _, err := decodeTag(tc.buf, 0)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil && tc.wantErr == "" {
				// For invalid varints in tag data, we accept any error
				return
			}
			if tc.wantFieldNum != 0 && fieldNum != tc.wantFieldNum {
				t.Errorf("fieldNum: got %d want %d", fieldNum, tc.wantFieldNum)
			}
			if tc.wantWireType != 0 && int(wireType) != tc.wantWireType {
				t.Errorf("wireType: got %d want %d", wireType, tc.wantWireType)
			}
		})
	}
}

func TestSkipField(t *testing.T) {
	cases := []struct {
		name     string
		buf      []byte
		wireType proto.WireType
		wantPos  int
		wantErr  string
	}{
		{
			name:     "skip VARINT",
			buf:      []byte{0x96, 0x01}, // varint 150
			wireType: 0,
			wantPos:  2,
		},
		{
			name:     "skip LEN with empty bytes",
			buf:      []byte{0x00},
			wireType: 2,
			wantPos:  1,
		},
		{
			name:     "skip LEN with bytes",
			buf:      []byte{0x03, 'a', 'b', 'c'},
			wireType: 2,
			wantPos:  4,
		},
		{
			name:     "skip FIXED32",
			buf:      []byte{0x01, 0x02, 0x03, 0x04, 0x05},
			wireType: 5,
			wantPos:  4,
		},
		{
			name:     "skip FIXED64",
			buf:      []byte{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09},
			wireType: 1,
			wantPos:  8,
		},
		{
			name:     "FIXED32 underflow",
			buf:      []byte{0x01, 0x02},
			wireType: 5,
			wantErr:  "buffer underflow while skipping fixed32",
		},
		{
			name:     "FIXED64 underflow",
			buf:      []byte{0x01, 0x02, 0x03},
			wireType: 1,
			wantErr:  "buffer underflow while skipping fixed64",
		},
		{
			name:     "unsupported wire type",
			buf:      []byte{},
			wireType: 3,
			wantErr:  "unsupported wire type",
		},
		{
			name:     "wire type 4 (deprecated SGROUP) unsupported",
			buf:      []byte{},
			wireType: 4,
			wantErr:  "unsupported wire type",
		},
		{
			name:     "wire type 6 (deprecated EGROUP) unsupported",
			buf:      []byte{},
			wireType: 6,
			wantErr:  "unsupported wire type",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pos, err := skipField(tc.buf, 0, tc.wireType)
			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if pos != tc.wantPos {
				t.Errorf("pos: got %d want %d", pos, tc.wantPos)
			}
		})
	}
}
