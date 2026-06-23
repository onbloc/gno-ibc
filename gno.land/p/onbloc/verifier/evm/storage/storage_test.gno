package storage

import (
	"crypto/keccak256"
	"testing"

	"gno.land/p/onbloc/encoding/rlp"
)

func TestEncodeStorageValue(t *testing.T) {
	tests := []struct {
		name string
		word []byte
		want string
	}{
		{name: "zero", word: make([]byte, 32), want: "80"},
		{name: "single byte", word: WordFromUint64(0x7f), want: "7f"},
		{name: "short string", word: WordFromUint64(0x80), want: "8180"},
		{name: "two bytes", word: WordFromUint64(0x0100), want: "820100"},
		{name: "all ones", word: bytesRepeat(0xff, 32), want: "a0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},
		{name: "leading zeroes trimmed", word: append(bytesRepeat(0x00, 30), 0x01, 0x02), want: "820102"},
		{name: "first byte nonzero keeps full word", word: append([]byte{0x01}, bytesRepeat(0x00, 31)...), want: "a00100000000000000000000000000000000000000000000000000000000000000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := EncodeStorageValue(tt.word)
			if err != nil {
				t.Fatalf("EncodeStorageValue: %v", err)
			}
			assertHex(t, "EncodeStorageValue", got, tt.want)
		})
	}
}

func TestEncodeStorageValueRejectsInvalidWord(t *testing.T) {
	if _, err := EncodeStorageValue(make([]byte, 31)); err != ErrInvalidValueLength {
		t.Fatalf("EncodeStorageValue: got %v want %v", err, ErrInvalidValueLength)
	}
}

func TestVerifyProof(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		slot := wordWithLastByte(0x01)
		value := WordFromUint64(0x1234)
		path := keccak256.Sum256(slot)

		leaf := node(leafPath(nibbles(path[:])), rlp.EncodeBytes(mustEncode(t, value)))
		root := hash(leaf)

		proof := Proof{Key: slot, Value: value, Proof: [][]byte{leaf}}
		if err := VerifyProof(root[:], proof); err != nil {
			t.Fatalf("VerifyProof: %v", err)
		}
	})

	t.Run("wrong value", func(t *testing.T) {
		slot := wordWithLastByte(0x01)
		value := WordFromUint64(0x1234)
		path := keccak256.Sum256(slot)

		leaf := node(leafPath(nibbles(path[:])), rlp.EncodeBytes(mustEncode(t, value)))
		root := hash(leaf)

		wrong := WordFromUint64(0x1235)
		proof := Proof{Key: slot, Value: wrong, Proof: [][]byte{leaf}}
		if err := VerifyProof(root[:], proof); err == nil {
			t.Fatalf("VerifyProof accepted wrong value")
		}
	})

	t.Run("invalid root", func(t *testing.T) {
		slot := wordWithLastByte(0x01)
		value := WordFromUint64(0x1234)

		proof := Proof{Key: slot, Value: value, Proof: [][]byte{}}
		if err := VerifyProof(make([]byte, 31), proof); err != ErrInvalidRootLength {
			t.Fatalf("VerifyProof invalid root: got %v want %v", err, ErrInvalidRootLength)
		}
	})

	t.Run("invalid key", func(t *testing.T) {
		root := make([]byte, 32)
		value := WordFromUint64(0x1234)

		proof := Proof{Key: make([]byte, 31), Value: value, Proof: [][]byte{}}
		if err := VerifyProof(root, proof); err != ErrInvalidKeyLength {
			t.Fatalf("VerifyProof invalid key: got %v want %v", err, ErrInvalidKeyLength)
		}
	})

	t.Run("invalid value", func(t *testing.T) {
		root := make([]byte, 32)
		slot := wordWithLastByte(0x01)

		proof := Proof{Key: slot, Value: make([]byte, 31), Proof: [][]byte{}}
		if err := VerifyProof(root, proof); err != ErrInvalidValueLength {
			t.Fatalf("VerifyProof invalid value: got %v want %v", err, ErrInvalidValueLength)
		}
	})
}

func TestVerifyAbsence(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		slot := wordWithLastByte(0x01)
		value := WordFromUint64(0x1234)
		path := keccak256.Sum256(slot)
		leaf := node(leafPath(nibbles(path[:])), rlp.EncodeBytes(mustEncode(t, value)))
		root := hash(leaf)

		missing := wordWithLastByte(0x02)
		if err := VerifyAbsence(root[:], Proof{Key: missing, Proof: [][]byte{leaf}}); err != nil {
			t.Fatalf("VerifyAbsence: %v", err)
		}
	})

	t.Run("present key rejected", func(t *testing.T) {
		slot := wordWithLastByte(0x01)
		value := WordFromUint64(0x1234)
		path := keccak256.Sum256(slot)
		leaf := node(leafPath(nibbles(path[:])), rlp.EncodeBytes(mustEncode(t, value)))
		root := hash(leaf)

		if err := VerifyAbsence(root[:], Proof{Key: slot, Proof: [][]byte{leaf}}); err == nil {
			t.Fatalf("VerifyAbsence accepted present key")
		}
	})

	t.Run("invalid root", func(t *testing.T) {
		slot := wordWithLastByte(0x01)
		proof := Proof{Key: slot, Proof: [][]byte{}}
		if err := VerifyAbsence(make([]byte, 31), proof); err != ErrInvalidRootLength {
			t.Fatalf("VerifyAbsence invalid root: got %v want %v", err, ErrInvalidRootLength)
		}
	})

	t.Run("invalid key", func(t *testing.T) {
		root := make([]byte, 32)
		proof := Proof{Key: make([]byte, 31), Proof: [][]byte{}}
		if err := VerifyAbsence(root, proof); err != ErrInvalidKeyLength {
			t.Fatalf("VerifyAbsence invalid key: got %v want %v", err, ErrInvalidKeyLength)
		}
	})

	t.Run("value ignored", func(t *testing.T) {
		root := mptEmptyRoot()
		slot := wordWithLastByte(0x01)
		// Value field should be ignored for absence proofs
		proof := Proof{Key: slot, Value: []byte{0x01}, Proof: [][]byte{}}
		if err := VerifyAbsence(root, proof); err != nil {
			t.Fatalf("VerifyAbsence with value: got %v want nil", err)
		}
	})
}

func TestCheckValue(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		value := WordFromUint64(0x1234)
		proof := Proof{Value: value}
		if err := CheckValue(proof, value); err != nil {
			t.Fatalf("CheckValue: %v", err)
		}
	})

	t.Run("mismatch", func(t *testing.T) {
		value := WordFromUint64(0x1234)
		expected := WordFromUint64(0x1235)
		proof := Proof{Value: value}
		if err := CheckValue(proof, expected); err != ErrValueMismatch {
			t.Fatalf("CheckValue mismatch: got %v want %v", err, ErrValueMismatch)
		}
	})

	t.Run("invalid proof value", func(t *testing.T) {
		value := WordFromUint64(0x1234)
		proof := Proof{Value: value[:31]}
		expected := WordFromUint64(0x1235)
		if err := CheckValue(proof, expected); err != ErrInvalidValueLength {
			t.Fatalf("CheckValue invalid proof value: got %v want %v", err, ErrInvalidValueLength)
		}
	})

	t.Run("invalid expected value", func(t *testing.T) {
		value := WordFromUint64(0x1234)
		proof := Proof{Value: value}
		expected := value[:31]
		if err := CheckValue(proof, expected); err != ErrInvalidValueLength {
			t.Fatalf("CheckValue invalid expected value: got %v want %v", err, ErrInvalidValueLength)
		}
	})
}

func TestVerifyGethStorageProofFixture(t *testing.T) {
	// Deterministic fixture generated by:
	// /tools/gen-ethereum-storage-proof-fixture/main.go
	//
	// The generator uses go-ethereum's trie.Prove API and follows the proof
	// construction pattern from go-ethereum's own trie proof tests:
	// https://github.com/ethereum/go-ethereum/blob/master/trie/proof_test.go
	//
	// Fixture contents:
	// - storage root: f63a6a9bb2fd470d31ebcc3d3a32363b987e037b88b88ca8e725f4a63f8de467
	// - membership slot: uint256(2)
	// - membership value: uint256(0xdeadbeef)
	// - absence slot: uint256(4)
	root := mustHex("f63a6a9bb2fd470d31ebcc3d3a32363b987e037b88b88ca8e725f4a63f8de467")
	slot := WordFromUint64(2)
	value := WordFromUint64(0xdeadbeef)
	proof := [][]byte{
		mustHex("f87180808080a04025f53b1cf482f141a575cb5ac55f36dbd11d0c0c13827bc0de3cc8a664e849808080808080a0107fa2f10231df59598f8a6787f84ad9943e8535cc92157d2a8eed68a33a24dda0524e1f771323723528ee31a971247f76a1433ba182566d18ece3f3bc6ae244b080808080"),
		mustHex("e7a0305787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ace8584deadbeef"),
	}

	if err := VerifyProof(root, Proof{Key: slot, Value: value, Proof: proof}); err != nil {
		t.Fatalf("VerifyProof geth fixture: %v", err)
	}

	missingSlot := WordFromUint64(4)
	absenceProof := [][]byte{proof[0]}
	if err := VerifyAbsence(root, Proof{Key: missingSlot, Proof: absenceProof}); err != nil {
		t.Fatalf("VerifyAbsence geth fixture: %v", err)
	}
}

func TestStoragePath(t *testing.T) {
	tests := []struct {
		name string
		slot []byte
		want string
		err  error
	}{
		{name: "invalid short slot", slot: make([]byte, 31), err: ErrInvalidKeyLength},
		{name: "zero slot", slot: make([]byte, 32), want: "290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563"},
		{name: "slot two", slot: WordFromUint64(2), want: "405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ace"},
		{name: "all ones", slot: bytesRepeat(0xff, 32), want: "a9c584056064687e149968cbab758a3376d22aedc6a55823d1b3ecbee81b8fb9"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := StoragePath(tt.slot)
			if err != tt.err {
				t.Fatalf("StoragePath: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			assertHex(t, "StoragePath", got[:], tt.want)
		})
	}
}

func TestIBCCommitmentKey(t *testing.T) {
	// These vectors intentionally pin both sides of the contract:
	// - Union: ethereum::ibc_commitment_key(path), fixed commitments slot 0.
	// - Ethereum: Solidity mapping(bytes32 => bytes32) storage layout.
	//
	// Union reference:
	// https://github.com/unionlabs/union/blob/main/lib/unionlabs/src/ethereum.rs
	// Ethereum reference:
	// https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html#mappings-and-dynamic-arrays
	tests := []struct {
		name             string
		path             []byte
		unionExpected    string
		ethereumExpected string
	}{
		{
			name:             "all 0x11 path",
			path:             mustHex("1111111111111111111111111111111111111111111111111111111111111111"),
			unionExpected:    "5c75bb376affa44a4f06c8a768453c2f7945122a65eb322a0dd3cc2edcbd6f0a",
			ethereumExpected: "5c75bb376affa44a4f06c8a768453c2f7945122a65eb322a0dd3cc2edcbd6f0a",
		},
		{
			name:             "zero path",
			path:             make([]byte, 32),
			unionExpected:    "ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5",
			ethereumExpected: "ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5",
		},
	}

	for _, tt := range tests {
		got, err := IBCCommitmentKey(tt.path)
		if err != nil {
			t.Fatalf("%s IBCCommitmentKey: %v", tt.name, err)
		}
		if tt.unionExpected != tt.ethereumExpected {
			t.Fatalf("%s reference mismatch: union %s ethereum %s", tt.name, tt.unionExpected, tt.ethereumExpected)
		}
		assertHex(t, tt.name+" union reference", got[:], tt.unionExpected)

		ethereumGot := ethereumMappingBytes32Slot0(tt.path)
		assertHex(t, tt.name+" ethereum reference", ethereumGot[:], tt.ethereumExpected)
	}

	if _, err := IBCCommitmentKey(tests[0].path[:31]); err != ErrInvalidPathLength {
		t.Fatalf("path length: got %v want %v", err, ErrInvalidPathLength)
	}
}

func TestValidateWord(t *testing.T) {
	sentinel := ErrInvalidKeyLength
	tests := []struct {
		name string
		word []byte
		err  error
	}{
		{name: "nil", word: nil, err: sentinel},
		{name: "short", word: make([]byte, 31), err: sentinel},
		{name: "exact", word: make([]byte, 32)},
		{name: "long", word: make([]byte, 33), err: sentinel},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := validateWord(tt.word, sentinel); err != tt.err {
				t.Fatalf("validateWord: got %v want %v", err, tt.err)
			}
		})
	}
}

func TestTrimLeadingZeroes(t *testing.T) {
	tests := []struct {
		name string
		word []byte
		want []byte
	}{
		{name: "nil", word: nil, want: nil},
		{name: "all zeroes", word: []byte{0x00, 0x00}, want: []byte{}},
		{name: "all ones", word: []byte{0xff, 0xff}, want: []byte{0xff, 0xff}},
		{name: "leading zeroes", word: []byte{0x00, 0x00, 0x01, 0x02}, want: []byte{0x01, 0x02}},
		{name: "first byte nonzero", word: []byte{0x01, 0x00}, want: []byte{0x01, 0x00}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := trimLeadingZeroes(tt.word); !bytesEqual(got, tt.want) {
				t.Fatalf("trimLeadingZeroes: got %x want %x", got, tt.want)
			}
		})
	}
}

func TestWordFromUint64(t *testing.T) {
	tests := []struct {
		name string
		v    uint64
		want string
	}{
		{name: "zero", v: 0, want: "0000000000000000000000000000000000000000000000000000000000000000"},
		{name: "one", v: 1, want: "0000000000000000000000000000000000000000000000000000000000000001"},
		{name: "max", v: ^uint64(0), want: "000000000000000000000000000000000000000000000000ffffffffffffffff"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertHex(t, "WordFromUint64", WordFromUint64(tt.v), tt.want)
		})
	}
}

func TestRejectInvalidWordLengths(t *testing.T) {
	root := make([]byte, 32)
	slot := make([]byte, 32)
	value := make([]byte, 32)

	if err := VerifyProof(root[:31], Proof{Key: slot, Value: value}); err != ErrInvalidRootLength {
		t.Fatalf("root length: got %v want %v", err, ErrInvalidRootLength)
	}
	if err := VerifyProof(root, Proof{Key: slot[:31], Value: value}); err != ErrInvalidKeyLength {
		t.Fatalf("key length: got %v want %v", err, ErrInvalidKeyLength)
	}
	if err := VerifyProof(root, Proof{Key: slot, Value: value[:31]}); err != ErrInvalidValueLength {
		t.Fatalf("value length: got %v want %v", err, ErrInvalidValueLength)
	}
	if _, err := StoragePath(slot[:31]); err != ErrInvalidKeyLength {
		t.Fatalf("StoragePath length: got %v want %v", err, ErrInvalidKeyLength)
	}
}
