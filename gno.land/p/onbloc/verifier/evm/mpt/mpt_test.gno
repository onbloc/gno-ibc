package mpt

import (
	"bytes"
	"crypto/keccak256"
	"testing"

	"gno.land/p/onbloc/encoding/rlp"
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

func TestEmptyRoot(t *testing.T) {
	root := EmptyRoot()
	want := keccak256.Sum256(rlp.EncodeBytes(nil))
	if !bytes.Equal(root[:], want[:]) {
		t.Fatalf("EmptyRoot: got %x want %x", root, want)
	}
}

func TestRejectsBadRootAndMissingHashedChild(t *testing.T) {
	value := bytes.Repeat([]byte{0x77}, 64)
	leaf := node(leafPath([]byte{0x0b}), rlp.EncodeBytes(value))
	leafHash := hash(leaf)
	wrongLeaf := node(leafPath([]byte{0x0b}), rlp.EncodeBytes([]byte("wrong")))

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
	if err := Verify(root[:], []byte{0xab}, value, [][]byte{branch, wrongLeaf}); err != ErrInvalidReference {
		t.Fatalf("hashed child mismatch: got %v want %v", err, ErrInvalidReference)
	}
	if err := Verify(root[:], []byte{0xab}, value, [][]byte{branch, leaf, leaf}); err != ErrUnusedProof {
		t.Fatalf("unused proof: got %v want %v", err, ErrUnusedProof)
	}
}

func TestRejectsUnexpectedNodeShapes(t *testing.T) {
	tests := []struct {
		name  string
		key   []byte
		proof [][]byte
	}{
		{
			name:  "root is string",
			key:   []byte{},
			proof: [][]byte{rlp.EncodeBytes([]byte("not-list"))},
		},
		{
			name: "branch value is list",
			key:  []byte{},
			proof: func() [][]byte {
				children := emptyBranch()
				children[16] = rlp.EncodeList()
				return [][]byte{rlp.EncodeList(children...)}
			}(),
		},
		{
			name: "branch child is list",
			key:  []byte{0x00},
			proof: func() [][]byte {
				children := emptyBranch()
				children[0] = rlp.EncodeList()
				return [][]byte{rlp.EncodeList(children...)}
			}(),
		},
		{
			name:  "extension path is list",
			key:   []byte{0x12},
			proof: [][]byte{rlp.EncodeList(rlp.EncodeList(), rlp.EncodeBytes(nil))},
		},
		{
			name:  "leaf value is list",
			key:   []byte{},
			proof: [][]byte{node(leafPath(nil), rlp.EncodeList())},
		},
		{
			name:  "list has unsupported length",
			key:   []byte{},
			proof: [][]byte{rlp.EncodeList(rlp.EncodeBytes(nil))},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			root := hash(tt.proof[0])
			if err := Verify(root[:], tt.key, nil, tt.proof); err != ErrUnexpectedNode {
				t.Fatalf("Verify: got %v want %v", err, ErrUnexpectedNode)
			}
		})
	}
}

func TestCompactDecodeRejectsEmptyExtension(t *testing.T) {
	if _, _, err := compactDecode(extensionPath(nil)); err != ErrPathMismatch {
		t.Fatalf("empty extension path: got %v want %v", err, ErrPathMismatch)
	}

	// A leaf with an empty path is canonical and must still decode.
	leaf, partial, err := compactDecode(leafPath(nil))
	if err != nil {
		t.Fatalf("empty leaf path: %v", err)
	}
	if !leaf || len(partial) != 0 {
		t.Fatalf("empty leaf path: got leaf=%v partial=%v", leaf, partial)
	}
}

func TestInternalHelpers(t *testing.T) {
	t.Run("isBytesNode", func(t *testing.T) {
		tests := []struct {
			name string
			v    rlp.Value
			want bool
		}{
			{name: "byte", v: rlp.Value{Kind: rlp.KindByte, Bytes: []byte{0x7f}}, want: true},
			{name: "string", v: rlp.Value{Kind: rlp.KindString, Bytes: []byte("dog")}, want: true},
			{name: "list", v: rlp.Value{Kind: rlp.KindList, List: []rlp.Value{}}, want: false},
		}

		for _, tt := range tests {
			if got := isBytesNode(tt.v); got != tt.want {
				t.Fatalf("%s: got %v want %v", tt.name, got, tt.want)
			}
		}
	})

	t.Run("matchHash", func(t *testing.T) {
		encoded := node(leafPath(nil), rlp.EncodeBytes([]byte("dog")))
		good := hash(encoded)
		bad := good
		bad[0] ^= 0xff
		tests := []struct {
			name string
			root []byte
			err  error
		}{
			{name: "match", root: good[:]},
			{name: "mismatch", root: bad[:], err: ErrInvalidReference},
		}

		for _, tt := range tests {
			if err := matchHash(tt.root, encoded); err != tt.err {
				t.Fatalf("%s: got %v want %v", tt.name, err, tt.err)
			}
		}
	})

	t.Run("resolveReference", func(t *testing.T) {
		embedded := node(leafPath(nil), rlp.EncodeBytes([]byte("dog")))
		hashed := bytes.Repeat([]byte{0x77}, 64)
		hashedRef := hash(hashed)
		invalidLong := append(hashedRef[:], 0x00)
		tests := []struct {
			name      string
			ref       []byte
			proof     [][]byte
			proofIdx  int
			wantNode  []byte
			wantIndex int
			err       error
		}{
			{name: "empty ref", ref: nil, proofIdx: 0, err: ErrInvalidReference},
			{name: "embedded short ref", ref: embedded, proofIdx: 0, wantNode: embedded, wantIndex: 0},
			{name: "invalid long ref", ref: invalidLong, proofIdx: 0, err: ErrInvalidReference},
			{name: "missing hashed child", ref: hashedRef[:], proof: [][]byte{embedded}, proofIdx: 0, err: ErrEmptyProof},
			{name: "hashed child", ref: hashedRef[:], proof: [][]byte{embedded, hashed}, proofIdx: 0, wantNode: hashed, wantIndex: 1},
		}

		for _, tt := range tests {
			gotNode, gotIndex, err := resolveReference(tt.ref, tt.proof, tt.proofIdx)
			if err != tt.err {
				t.Fatalf("%s: got err %v want %v", tt.name, err, tt.err)
			}
			if err != nil {
				continue
			}
			if gotIndex != tt.wantIndex || !bytes.Equal(gotNode, tt.wantNode) {
				t.Fatalf("%s: got node=%x index=%d want node=%x index=%d", tt.name, gotNode, gotIndex, tt.wantNode, tt.wantIndex)
			}
		}
	})

	t.Run("keybytesToNibbles", func(t *testing.T) {
		tests := []struct {
			name string
			key  []byte
			want []byte
		}{
			{name: "empty", key: nil, want: nil},
			{name: "single byte", key: []byte{0xab}, want: []byte{0x0a, 0x0b}},
			{name: "two bytes", key: []byte{0x01, 0xf0}, want: []byte{0x00, 0x01, 0x0f, 0x00}},
		}

		for _, tt := range tests {
			if got := keybytesToNibbles(tt.key); !bytes.Equal(got, tt.want) {
				t.Fatalf("%s: got %x want %x", tt.name, got, tt.want)
			}
		}
	})

	t.Run("compactDecode", func(t *testing.T) {
		tests := []struct {
			name        string
			encoded     []byte
			wantLeaf    bool
			wantPartial []byte
			err         error
		}{
			{name: "empty input", encoded: nil, err: ErrPathMismatch},
			{name: "invalid flag", encoded: []byte{0x40}, err: ErrPathMismatch},
			{name: "even path low nibble nonzero", encoded: []byte{0x01}, err: ErrPathMismatch},
			{name: "empty extension", encoded: extensionPath(nil), err: ErrPathMismatch},
			{name: "empty leaf", encoded: leafPath(nil), wantLeaf: true, wantPartial: nil},
			{name: "odd extension", encoded: extensionPath([]byte{0x0a, 0x0b, 0x0c}), wantPartial: []byte{0x0a, 0x0b, 0x0c}},
			{name: "even leaf", encoded: leafPath([]byte{0x01, 0x02}), wantLeaf: true, wantPartial: []byte{0x01, 0x02}},
		}

		for _, tt := range tests {
			gotLeaf, gotPartial, err := compactDecode(tt.encoded)
			if err != tt.err {
				t.Fatalf("%s: got err %v want %v", tt.name, err, tt.err)
			}
			if err != nil {
				continue
			}
			if gotLeaf != tt.wantLeaf || !bytes.Equal(gotPartial, tt.wantPartial) {
				t.Fatalf("%s: got leaf=%v partial=%x want leaf=%v partial=%x", tt.name, gotLeaf, gotPartial, tt.wantLeaf, tt.wantPartial)
			}
		}
	})

	t.Run("hasPrefix", func(t *testing.T) {
		tests := []struct {
			name   string
			path   []byte
			prefix []byte
			want   bool
		}{
			{name: "empty prefix", path: []byte{0x01}, prefix: nil, want: true},
			{name: "both empty", path: nil, prefix: nil, want: true},
			{name: "prefix longer", path: []byte{0x01}, prefix: []byte{0x01, 0x02}, want: false},
			{name: "matches", path: []byte{0x01, 0x02, 0x03}, prefix: []byte{0x01, 0x02}, want: true},
			{name: "mismatch", path: []byte{0x01, 0x02}, prefix: []byte{0x01, 0x03}, want: false},
		}

		for _, tt := range tests {
			if got := hasPrefix(tt.path, tt.prefix); got != tt.want {
				t.Fatalf("%s: got %v want %v", tt.name, got, tt.want)
			}
		}
	})
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
