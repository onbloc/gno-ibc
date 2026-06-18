package types

import "crypto/keccak256"

// Keccak hashes bz with keccak256 and returns the result as an H256.
// Exported for realm callers (core commits state roots with it).
func Keccak(bz []byte) H256 { return keccak(bz) }

// keccak hashes bz with keccak256 and returns the result as an H256.
// Used by the commitment path/encoding helpers.
func keccak(bz []byte) H256 {
	sum := keccak256.Sum256(bz)

	var out H256

	for i := range out {
		out[i] = sum[i]
	}

	return out
}
