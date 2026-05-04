package smoke

import (
	"encoding/hex"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

// TestStdlibSizes asserts the CometBLS-fork stdlib constants have the values
// the rest of the Phase 3/4 port assumes (Keccak Size=32, LightHeader=116,
// BN254 EIP-196/197 sizes). If any of these change upstream, the rest of the
// port needs to be audited.
func TestStdlibSizes(t *testing.T) {
	if KeccakSize != 32 {
		t.Fatalf("keccak size: got %d want 32", KeccakSize)
	}
	if CometblsHeaderSize != 116 {
		t.Fatalf("cometbls LightHeader size: got %d want 116", CometblsHeaderSize)
	}
	if CometblszkHeaderSize != CometblsHeaderSize {
		t.Fatalf("cometbls vs cometblszk header size mismatch: %d vs %d",
			CometblsHeaderSize, CometblszkHeaderSize)
	}
	if BN254G1Add != 128 || BN254G1Mul != 96 || BN254G1Out != 64 {
		t.Fatalf("BN254 G1 sizes: add=%d mul=%d out=%d", BN254G1Add, BN254G1Mul, BN254G1Out)
	}
	if BN254PairChunk != 192 || BN254PairOutput != 32 {
		t.Fatalf("BN254 pairing sizes: chunk=%d out=%d", BN254PairChunk, BN254PairOutput)
	}
}

func TestKeccakEmpty(t *testing.T) {
	got := HashEmpty()
	want := "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
	if h := hex.EncodeToString(got[:]); h != want {
		t.Fatalf("keccak256(\"\"): got %s want %s", h, want)
	}
}

func TestModExpSmall(t *testing.T) {
	got := ModExpOne()
	if len(got) != 1 || got[0] != 2 {
		t.Fatalf("modexp(2,1,5): got %v want [2]", got)
	}
}

func TestUint256Add(t *testing.T) {
	got := AddOneTwo()
	want := u256.NewUint(3)
	if got.Cmp(want) != 0 {
		t.Fatalf("AddOneTwo: got %s want %s", got.ToString(), want.ToString())
	}
}
