package types

import "crypto/keccak256"

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
