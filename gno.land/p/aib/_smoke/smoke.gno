// Package smoke confirms that the gno toolchain can resolve and link the
// five native stdlib packages vendored under stdlibs/ (bn254, cometbls,
// cometblszk, keccak256, modexp) that the CometBLS + ZKGM port depends on,
// plus the vendored gnoswap/uint256.
//
// This package exists only to validate the environment. It is safe to delete
// once the rest of Wave 0 is in place.
package smoke

import (
	"crypto/bn254"
	"crypto/cometbls"
	"crypto/cometblszk"
	"crypto/keccak256"
	"crypto/modexp"

	u256 "gno.land/p/gnoswap/uint256"
)

// AddOneTwo returns 1 + 2 = 3 as a uint256, exercising the gnoswap/uint256
// import end-to-end (allocate, arithmetic, equality).
func AddOneTwo() *u256.Uint {
	a := u256.NewUint(1)
	b := u256.NewUint(2)
	return new(u256.Uint).Add(a, b)
}

// KeccakSize is re-exported from crypto/keccak256.
const KeccakSize = keccak256.Size

// CometblsHeaderSize is re-exported from crypto/cometbls.
const CometblsHeaderSize = cometbls.EncodedLightHeaderSize

// CometblszkHeaderSize is re-exported from crypto/cometblszk and must match
// CometblsHeaderSize — both packages share the bespoke 116-byte LightHeader
// encoding.
const CometblszkHeaderSize = cometblszk.EncodedLightHeaderSize

// BN254 sizes — surfaced so a test can check the constants are reachable.
const (
	BN254G1Add      = bn254.G1AddInputSize
	BN254G1Mul      = bn254.G1MulInputSize
	BN254G1Out      = bn254.G1OutputSize
	BN254PairChunk  = bn254.PairingChunkSize
	BN254PairOutput = bn254.PairingOutputSize
)

// HashEmpty returns keccak256("") — a fixed test vector.
func HashEmpty() [keccak256.Size]byte {
	return keccak256.Sum256(nil)
}

// ModExpOne returns 2^1 mod 5 = 2 in 1-byte big-endian form.
func ModExpOne() []byte {
	return modexp.ModExp([]byte{0x02}, []byte{0x01}, []byte{0x05})
}
