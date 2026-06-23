package mpt

import (
	"bytes"
	"crypto/keccak256"
	"testing"

	"gno.land/p/onbloc/encoding/rlp"
)

func TestEmptyRoot(t *testing.T) {
	root := EmptyRoot()
	want := keccak256.Sum256(rlp.EncodeBytes(nil))
	if !bytes.Equal(root[:], want[:]) {
		t.Fatalf("EmptyRoot: got %x want %x", root, want)
	}
}

func TestVerify(t *testing.T) {
	value := []byte("dog")
	leaf := node(leafPath([]byte{0x0a, 0x0b}), rlp.EncodeBytes(value))
	root := hash(leaf)

	tests := []struct {
		name  string
		root  []byte
		key   []byte
		value []byte
		proof [][]byte
		err   error
	}{
		{name: "matching leaf", root: root[:], key: []byte{0xab}, value: value, proof: [][]byte{leaf}},
		{name: "wrong key", root: root[:], key: []byte{0xac}, value: value, proof: [][]byte{leaf}, err: ErrKeyAbsent},
		{name: "wrong value", root: root[:], key: []byte{0xab}, value: []byte("cat"), proof: [][]byte{leaf}, err: ErrValueMismatch},
		{name: "empty root", root: hashBytes(rlp.EncodeBytes(nil)), key: []byte{0xab}, value: []byte("dog"), err: ErrKeyAbsent},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := Verify(tt.root, tt.key, tt.value, tt.proof); err != tt.err {
				t.Fatalf("Verify: got %v want %v", err, tt.err)
			}
		})
	}
}

func TestVerifyAbsence(t *testing.T) {
	value := []byte("dog")
	leaf := node(leafPath([]byte{0x0a, 0x0b}), rlp.EncodeBytes(value))
	root := hash(leaf)

	children := emptyBranch()
	branch := rlp.EncodeList(children...)
	branchRoot := hash(branch)

	tests := []struct {
		name  string
		root  []byte
		key   []byte
		proof [][]byte
		err   error
	}{
		{name: "leaf path mismatch", root: root[:], key: []byte{0xac}, proof: [][]byte{leaf}},
		{name: "present key", root: root[:], key: []byte{0xab}, proof: [][]byte{leaf}, err: ErrKeyPresent},
		{name: "empty branch child", root: branchRoot[:], key: []byte{0xab}, proof: [][]byte{branch}},
		{name: "empty root", root: hashBytes(rlp.EncodeBytes(nil)), key: []byte{0xab}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := VerifyAbsence(tt.root, tt.key, tt.proof); err != tt.err {
				t.Fatalf("VerifyAbsence: got %v want %v", err, tt.err)
			}
		})
	}
}

func TestIsBytesNode(t *testing.T) {
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
		t.Run(tt.name, func(t *testing.T) {
			if got := isBytesNode(tt.v); got != tt.want {
				t.Fatalf("isBytesNode: got %v want %v", got, tt.want)
			}
		})
	}
}

func TestWalk(t *testing.T) {
	longValue := bytes.Repeat([]byte{0x77}, 64)
	hashedLeaf := node(leafPath([]byte{0x0b}), rlp.EncodeBytes(longValue))
	hashedLeafRef := hash(hashedLeaf)
	hashedBranchChildren := emptyBranch()
	hashedBranchChildren[0x0a] = rlp.EncodeBytes(hashedLeafRef[:])
	hashedBranch := rlp.EncodeList(hashedBranchChildren...)

	embeddedValue := []byte("ok")
	embeddedLeaf := node(leafPath([]byte{0x03, 0x04}), rlp.EncodeBytes(embeddedValue))
	embeddedExt := node(extensionPath([]byte{0x01, 0x02}), rlp.EncodeBytes(embeddedLeaf))

	singleValue := []byte("dog")
	singleLeaf := node(leafPath([]byte{0x0a, 0x0b}), rlp.EncodeBytes(singleValue))

	emptyRoot := EmptyRoot()
	badRoot := hash(hashedBranch)
	badRoot[0] ^= 0xff

	tests := []struct {
		name      string
		root      []byte
		path      []byte
		proof     [][]byte
		wantFound bool
		wantValue []byte
		err       error
	}{
		{name: "single leaf", root: hashBytes(singleLeaf), path: []byte{0x0a, 0x0b}, proof: [][]byte{singleLeaf}, wantFound: true, wantValue: singleValue},
		{name: "leaf path mismatch", root: hashBytes(singleLeaf), path: []byte{0x0a, 0x0c}, proof: [][]byte{singleLeaf}},
		{name: "embedded extension leaf", root: hashBytes(embeddedExt), path: []byte{0x01, 0x02, 0x03, 0x04}, proof: [][]byte{embeddedExt}, wantFound: true, wantValue: embeddedValue},
		{name: "hashed branch child", root: hashBytes(hashedBranch), path: []byte{0x0a, 0x0b}, proof: [][]byte{hashedBranch, hashedLeaf}, wantFound: true, wantValue: longValue},
		{name: "empty branch child", root: hashBytes(rlp.EncodeList(emptyBranch()...)), path: []byte{0x0a, 0x0b}, proof: [][]byte{rlp.EncodeList(emptyBranch()...)}},
		{name: "empty root without proof", root: emptyRoot[:], path: []byte{0x0a, 0x0b}},
		{name: "invalid root length", root: []byte{0x01}, path: nil, err: ErrInvalidRoot},
		{name: "non-empty root without proof", root: hashBytes(singleLeaf), path: nil, err: ErrEmptyProof},
		{name: "bad root", root: badRoot[:], path: []byte{0x0a, 0x0b}, proof: [][]byte{hashedBranch, hashedLeaf}, err: ErrInvalidReference},
		{name: "missing hashed child", root: hashBytes(hashedBranch), path: []byte{0x0a, 0x0b}, proof: [][]byte{hashedBranch}, err: ErrEmptyProof},
		{name: "hashed child mismatch", root: hashBytes(hashedBranch), path: []byte{0x0a, 0x0b}, proof: [][]byte{hashedBranch, node(leafPath([]byte{0x0b}), rlp.EncodeBytes([]byte("wrong")))}, err: ErrInvalidReference},
		{name: "unused proof", root: hashBytes(hashedBranch), path: []byte{0x0a, 0x0b}, proof: [][]byte{hashedBranch, hashedLeaf, hashedLeaf}, err: ErrUnusedProof},
		{name: "root is string", root: hashBytes(rlp.EncodeBytes([]byte("not-list"))), proof: [][]byte{rlp.EncodeBytes([]byte("not-list"))}, err: ErrUnexpectedNode},
		{name: "branch value is list", root: hashBytes(branchWithValue(rlp.EncodeList())), proof: [][]byte{branchWithValue(rlp.EncodeList())}, err: ErrUnexpectedNode},
		{name: "branch child is list", root: hashBytes(branchWithChild(0, rlp.EncodeList())), path: []byte{0x00}, proof: [][]byte{branchWithChild(0, rlp.EncodeList())}, err: ErrUnexpectedNode},
		{name: "extension path is list", root: hashBytes(rlp.EncodeList(rlp.EncodeList(), rlp.EncodeBytes(nil))), path: []byte{0x01, 0x02}, proof: [][]byte{rlp.EncodeList(rlp.EncodeList(), rlp.EncodeBytes(nil))}, err: ErrUnexpectedNode},
		{name: "leaf value is list", root: hashBytes(node(leafPath(nil), rlp.EncodeList())), proof: [][]byte{node(leafPath(nil), rlp.EncodeList())}, err: ErrUnexpectedNode},
		{name: "list has unsupported length", root: hashBytes(rlp.EncodeList(rlp.EncodeBytes(nil))), proof: [][]byte{rlp.EncodeList(rlp.EncodeBytes(nil))}, err: ErrUnexpectedNode},
		{name: "branch terminal value", root: hashBytes(branchWithValue(rlp.EncodeBytes([]byte("terminal")))), path: []byte{}, proof: [][]byte{branchWithValue(rlp.EncodeBytes([]byte("terminal")))}, wantFound: true, wantValue: []byte("terminal")},
		{name: "extension child is list", root: hashBytes(node(extensionPath([]byte{0x0a}), rlp.EncodeList())), path: []byte{0x0a}, proof: [][]byte{node(extensionPath([]byte{0x0a}), rlp.EncodeList())}, err: ErrUnexpectedNode},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := walk(tt.root, tt.path, tt.proof)
			if err != tt.err {
				t.Fatalf("walk: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			if got.found != tt.wantFound || !bytes.Equal(got.value, tt.wantValue) {
				t.Fatalf("walk: got found=%v value=%x want found=%v value=%x", got.found, got.value, tt.wantFound, tt.wantValue)
			}
		})
	}
}

func TestFinishWalk(t *testing.T) {
	tests := []struct {
		name       string
		proofIndex int
		proof      [][]byte
		result     walkResult
		err        error
	}{
		{name: "last proof node", proofIndex: 0, proof: [][]byte{[]byte("root")}, result: walkResult{found: true, value: []byte("dog")}},
		{name: "unused proof node", proofIndex: 0, proof: [][]byte{[]byte("root"), []byte("extra")}, err: ErrUnusedProof},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := finishWalk(tt.result, tt.proofIndex, tt.proof)
			if err != tt.err {
				t.Fatalf("finishWalk: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			if got.found != tt.result.found || !bytes.Equal(got.value, tt.result.value) {
				t.Fatalf("finishWalk: got %+v want %+v", got, tt.result)
			}
		})
	}
}

func TestResolveReference(t *testing.T) {
	embedded := node(leafPath(nil), rlp.EncodeBytes([]byte("dog")))
	hashed := bytes.Repeat([]byte{0x77}, 64)
	hashedRef := hash(hashed)
	invalidLong := append(hashedRef[:], 0x00)
	badRef := hashedRef
	badRef[0] ^= 0xff

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
		{name: "hashed child mismatch", ref: badRef[:], proof: [][]byte{embedded, hashed}, proofIdx: 0, err: ErrInvalidReference},
		{name: "hashed child", ref: hashedRef[:], proof: [][]byte{embedded, hashed}, proofIdx: 0, wantNode: hashed, wantIndex: 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotNode, gotIndex, err := resolveReference(tt.ref, tt.proof, tt.proofIdx)
			if err != tt.err {
				t.Fatalf("resolveReference: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			if gotIndex != tt.wantIndex || !bytes.Equal(gotNode, tt.wantNode) {
				t.Fatalf("resolveReference: got node=%x index=%d want node=%x index=%d", gotNode, gotIndex, tt.wantNode, tt.wantIndex)
			}
		})
	}
}

func TestMatchHash(t *testing.T) {
	encoded := node(leafPath(nil), rlp.EncodeBytes([]byte("dog")))
	good := hash(encoded)
	bad := good
	bad[0] ^= 0xff

	tests := []struct {
		name     string
		expected []byte
		err      error
	}{
		{name: "match", expected: good[:]},
		{name: "mismatch", expected: bad[:], err: ErrInvalidReference},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := matchHash(tt.expected, encoded); err != tt.err {
				t.Fatalf("matchHash: got %v want %v", err, tt.err)
			}
		})
	}
}

func TestKeybytesToNibbles(t *testing.T) {
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
		t.Run(tt.name, func(t *testing.T) {
			if got := keybytesToNibbles(tt.key); !bytes.Equal(got, tt.want) {
				t.Fatalf("keybytesToNibbles: got %x want %x", got, tt.want)
			}
		})
	}
}

func TestCompactDecode(t *testing.T) {
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
		{name: "odd leaf", encoded: leafPath([]byte{0x0a, 0x0b, 0x0c}), wantLeaf: true, wantPartial: []byte{0x0a, 0x0b, 0x0c}},
		{name: "even leaf", encoded: leafPath([]byte{0x01, 0x02}), wantLeaf: true, wantPartial: []byte{0x01, 0x02}},
		{name: "even extension", encoded: extensionPath([]byte{0x01, 0x02}), wantPartial: []byte{0x01, 0x02}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotLeaf, gotPartial, err := compactDecode(tt.encoded)
			if err != tt.err {
				t.Fatalf("compactDecode: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			if gotLeaf != tt.wantLeaf || !bytes.Equal(gotPartial, tt.wantPartial) {
				t.Fatalf("compactDecode: got leaf=%v partial=%x want leaf=%v partial=%x", gotLeaf, gotPartial, tt.wantLeaf, tt.wantPartial)
			}
		})
	}
}

func TestHasPrefix(t *testing.T) {
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
		t.Run(tt.name, func(t *testing.T) {
			if got := hasPrefix(tt.path, tt.prefix); got != tt.want {
				t.Fatalf("hasPrefix: got %v want %v", got, tt.want)
			}
		})
	}
}
