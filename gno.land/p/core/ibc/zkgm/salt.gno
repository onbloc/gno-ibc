package zkgm

import (
	"crypto/keccak256"
	"encoding/binary"

	u256 "gno.land/p/gnoswap/uint256"
)

func DeriveBatchSalt(index *u256.Uint, salt [32]byte) [32]byte {
	var input [64]byte
	putUint256BE(input[:32], index)
	copy(input[32:], salt[:])
	return keccak256.Sum256(input[:])
}

func TintForwardSalt(salt [32]byte) [32]byte {
	var out [32]byte
	for i := range salt {
		out[i] = salt[i] | FORWARD_SALT_MAGIC[i]
	}
	return out
}

func IsForwardedPacket(salt [32]byte) bool {
	for i := range salt {
		if salt[i]&FORWARD_SALT_MAGIC[i] != FORWARD_SALT_MAGIC[i] {
			return false
		}
	}
	return true
}

func DeriveForwardSalt(salt [32]byte) [32]byte {
	hash := keccak256.Sum256(salt[:])
	return TintForwardSalt(hash)
}

// Uint256ToBytes32 returns the big-endian 32-byte encoding of x.
func Uint256ToBytes32(x *u256.Uint) [32]byte {
	var out [32]byte
	putUint256BE(out[:], x)
	return out
}

// TODO: depends on gnoswap/uint256's internal [4]uint64 layout (mirror of
// SetBytes32). Replace with the upstream Bytes32() method once it exists.
func putUint256BE(dst []byte, x *u256.Uint) {
	binary.BigEndian.PutUint64(dst[0:8], x[3])
	binary.BigEndian.PutUint64(dst[8:16], x[2])
	binary.BigEndian.PutUint64(dst[16:24], x[1])
	binary.BigEndian.PutUint64(dst[24:32], x[0])
}
