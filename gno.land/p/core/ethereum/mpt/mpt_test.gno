package mpt

import (
	"bytes"
	"crypto/keccak256"
	"testing"

	"gno.land/p/core/encoding/rlp"
)

func TestVerifySingleLeaf(t *testing.T) {
	value := []byte("dog")
	leaf := node(leafPath([]byte{0x0a, 0x0b}), rlp.EncodeBytes(value))
	root := hash(leaf)

	if err := Verify(root[:], []byte{0xab}, value, [][]byte{leaf}); err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if err := Verify(root[:], []byte{0xac}, value, [][]byte{leaf}); err != ErrKeyAbsent {
		t.Fatalf("wrong key: got %v want %v", err, ErrKeyAbsent)
	}
	if err := Verify(root[:], []byte{0xab}, []byte("cat"), [][]byte{leaf}); err != ErrValueMismatch {
		t.Fatalf("wrong value: got %v want %v", err, ErrValueMismatch)
	}
}

func TestVerifyEmbeddedExtensionLeaf(t *testing.T) {
	value := []byte("ok")
	leaf := node(leafPath([]byte{0x03, 0x04}), rlp.EncodeBytes(value))
	ext := node(extensionPath([]byte{0x01, 0x02}), rlp.EncodeBytes(leaf))
	root := hash(ext)

	if len(leaf) >= keccak256.Size {
		t.Fatalf("test leaf must be embedded, got len %d", len(leaf))
	}
	if err := Verify(root[:], []byte{0x12, 0x34}, value, [][]byte{ext}); err != nil {
		t.Fatalf("Verify: %v", err)
	}
}

func TestVerifyHashedBranchChild(t *testing.T) {
	value := bytes.Repeat([]byte{0x77}, 64)
	leaf := node(leafPath([]byte{0x0b}), rlp.EncodeBytes(value))
	leafHash := hash(leaf)

	children := emptyBranch()
	children[0x0a] = rlp.EncodeBytes(leafHash[:])
	branch := rlp.EncodeList(children...)
	root := hash(branch)

	if len(leaf) < keccak256.Size {
		t.Fatalf("test leaf must be hash referenced, got len %d", len(leaf))
	}
	if err := Verify(root[:], []byte{0xab}, value, [][]byte{branch, leaf}); err != nil {
		t.Fatalf("Verify: %v", err)
	}
}

func TestVerifyAbsence(t *testing.T) {
	value := []byte("dog")
	leaf := node(leafPath([]byte{0x0a, 0x0b}), rlp.EncodeBytes(value))
	root := hash(leaf)

	if err := VerifyAbsence(root[:], []byte{0xac}, [][]byte{leaf}); err != nil {
		t.Fatalf("VerifyAbsence leaf mismatch: %v", err)
	}
	if err := VerifyAbsence(root[:], []byte{0xab}, [][]byte{leaf}); err != ErrKeyPresent {
		t.Fatalf("present key: got %v want %v", err, ErrKeyPresent)
	}

	children := emptyBranch()
	branch := rlp.EncodeList(children...)
	branchRoot := hash(branch)
	if err := VerifyAbsence(branchRoot[:], []byte{0xab}, [][]byte{branch}); err != nil {
		t.Fatalf("VerifyAbsence empty branch child: %v", err)
	}
}

func TestVerifyAbsenceEmptyRoot(t *testing.T) {
	root := EmptyRoot()
	if err := VerifyAbsence(root[:], []byte{0xab}, nil); err != nil {
		t.Fatalf("VerifyAbsence empty root: %v", err)
	}
	if err := Verify(root[:], []byte{0xab}, []byte("dog"), nil); err != ErrKeyAbsent {
		t.Fatalf("Verify empty root: got %v want %v", err, ErrKeyAbsent)
	}
}

func TestRejectsBadRootAndMissingHashedChild(t *testing.T) {
	value := bytes.Repeat([]byte{0x77}, 64)
	leaf := node(leafPath([]byte{0x0b}), rlp.EncodeBytes(value))
	leafHash := hash(leaf)

	children := emptyBranch()
	children[0x0a] = rlp.EncodeBytes(leafHash[:])
	branch := rlp.EncodeList(children...)
	root := hash(branch)

	badRoot := make([]byte, len(root))
	copy(badRoot, root[:])
	badRoot[0] ^= 0xff
	if err := Verify(badRoot, []byte{0xab}, value, [][]byte{branch, leaf}); err != ErrInvalidReference {
		t.Fatalf("bad root: got %v want %v", err, ErrInvalidReference)
	}
	if err := Verify(root[:], []byte{0xab}, value, [][]byte{branch}); err != ErrEmptyProof {
		t.Fatalf("missing child: got %v want %v", err, ErrEmptyProof)
	}
	if err := Verify(root[:], []byte{0xab}, value, [][]byte{branch, leaf, leaf}); err != ErrUnusedProof {
		t.Fatalf("unused proof: got %v want %v", err, ErrUnusedProof)
	}
}

func node(path []byte, valueOrRef []byte) []byte {
	return rlp.EncodeList(rlp.EncodeBytes(path), valueOrRef)
}

func emptyBranch() [][]byte {
	children := make([][]byte, 17)
	for i := range children {
		children[i] = rlp.EncodeBytes(nil)
	}
	return children
}

func hash(encoded []byte) [32]byte {
	return keccak256.Sum256(encoded)
}

func leafPath(nibbles []byte) []byte {
	return compactEncode(true, nibbles)
}

func extensionPath(nibbles []byte) []byte {
	return compactEncode(false, nibbles)
}

func compactEncode(leaf bool, nibbles []byte) []byte {
	flag := byte(0)
	if leaf {
		flag = 2
	}
	odd := len(nibbles)%2 == 1
	out := make([]byte, 0, (len(nibbles)+2)/2)
	if odd {
		out = append(out, (flag+1)<<4|nibbles[0])
		nibbles = nibbles[1:]
	} else {
		out = append(out, flag<<4)
	}
	for i := 0; i < len(nibbles); i += 2 {
		out = append(out, nibbles[i]<<4|nibbles[i+1])
	}
	return out
}
