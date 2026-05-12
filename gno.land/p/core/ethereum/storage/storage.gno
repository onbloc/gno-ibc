package storage

import (
	"bytes"
	"crypto/keccak256"
	"encoding/binary"
	"errors"

	"gno.land/p/core/encoding/rlp"
	"gno.land/p/core/ethereum/mpt"
)

var (
	ErrInvalidRootLength  = errors.New("storage: root must be 32 bytes")
	ErrInvalidKeyLength   = errors.New("storage: key must be 32 bytes")
	ErrInvalidPathLength  = errors.New("storage: path must be 32 bytes")
	ErrInvalidValueLength = errors.New("storage: value must be 32 bytes")
	ErrValueMismatch      = errors.New("storage: value mismatch")
)

// Proof is the storage proof shape returned by eth_getProof for one slot,
// normalized to bytes. Key and Value are 32-byte EVM words. Proof contains the
// raw RLP-encoded trie nodes from root to leaf.
type Proof struct {
	Key   []byte
	Value []byte
	Proof [][]byte
}

// VerifyProof verifies that proof.Key stores proof.Value under storageRoot.
// Ethereum storage tries are keyed by keccak256(slot), and the leaf payload is
// the RLP encoding of the storage value with leading zero bytes removed.
func VerifyProof(storageRoot []byte, proof Proof) error {
	if err := validateWord(storageRoot, ErrInvalidRootLength); err != nil {
		return err
	}
	if err := validateWord(proof.Key, ErrInvalidKeyLength); err != nil {
		return err
	}
	if err := validateWord(proof.Value, ErrInvalidValueLength); err != nil {
		return err
	}
	path := keccak256.Sum256(proof.Key)
	return mpt.Verify(storageRoot, path[:], encodeStorageValue(proof.Value), proof.Proof)
}

// VerifyAbsence verifies that proof.Key is absent under storageRoot. The Value
// field is intentionally ignored for absence proofs because eth_getProof returns
// zero for missing slots.
func VerifyAbsence(storageRoot []byte, proof Proof) error {
	if err := validateWord(storageRoot, ErrInvalidRootLength); err != nil {
		return err
	}
	if err := validateWord(proof.Key, ErrInvalidKeyLength); err != nil {
		return err
	}
	path := keccak256.Sum256(proof.Key)
	return mpt.VerifyAbsence(storageRoot, path[:], proof.Proof)
}

// CheckValue verifies only the value reported by the proof object. This is
// useful when a caller receives an expected 32-byte commitment separately.
func CheckValue(proof Proof, expected []byte) error {
	if err := validateWord(proof.Value, ErrInvalidValueLength); err != nil {
		return err
	}
	if err := validateWord(expected, ErrInvalidValueLength); err != nil {
		return err
	}
	if !bytes.Equal(proof.Value, expected) {
		return ErrValueMismatch
	}
	return nil
}

// StoragePath returns the MPT path used for an EVM storage slot.
func StoragePath(slot []byte) ([32]byte, error) {
	if err := validateWord(slot, ErrInvalidKeyLength); err != nil {
		return [32]byte{}, err
	}
	return keccak256.Sum256(slot), nil
}

// IBCCommitmentKey mirrors Union's ethereum::ibc_commitment_key for
// mapping(bytes32 => bytes32) commitments at slot 0.
//
// Union reference:
// https://github.com/unionlabs/union/blob/main/lib/unionlabs/src/ethereum.rs
func IBCCommitmentKey(path []byte) ([32]byte, error) {
	if err := validateWord(path, ErrInvalidPathLength); err != nil {
		return [32]byte{}, err
	}
	var input [64]byte
	copy(input[0:32], path)
	return keccak256.Sum256(input[:]), nil
}

// EncodeStorageValue returns the leaf payload expected by the storage trie.
func EncodeStorageValue(word []byte) ([]byte, error) {
	if err := validateWord(word, ErrInvalidValueLength); err != nil {
		return nil, err
	}
	return encodeStorageValue(word), nil
}

func validateWord(word []byte, err error) error {
	if len(word) != 32 {
		return err
	}
	return nil
}

func encodeStorageValue(word []byte) []byte {
	return rlp.EncodeBytes(trimLeadingZeroes(word))
}

func trimLeadingZeroes(word []byte) []byte {
	i := 0
	for i < len(word) && word[i] == 0 {
		i++
	}
	return word[i:]
}

func WordFromUint64(v uint64) []byte {
	out := make([]byte, 32)
	binary.BigEndian.PutUint64(out[24:], v)
	return out
}
