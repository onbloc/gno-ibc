package zkgm

import (
	"encoding/hex"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestDeriveBatchSalt(t *testing.T) {
	salt := mustBytes32(t, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
	got := DeriveBatchSalt(u256.NewUint(1), salt)

	assertHex(t, "DeriveBatchSalt", got[:], "22270b886c360fef2a5742b5b6c4ea02426060d33d847bee59a6d7b2ef85de17")
}

func TestTintForwardSaltOK(t *testing.T) {
	salt := mustBytes32(t, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")

	if IsForwardedPacket(salt) {
		t.Fatal("raw salt was unexpectedly forwarded")
	}
	if !IsForwardedPacket(TintForwardSalt(salt)) {
		t.Fatal("tinted salt was not forwarded")
	}
}

func TestTintForwardSaltIdempotent(t *testing.T) {
	salt := mustBytes32(t, "fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321")
	tinted := TintForwardSalt(salt)

	if TintForwardSalt(tinted) != tinted {
		t.Fatal("TintForwardSalt is not idempotent")
	}
}

func TestTintForwardSaltPreservesDataBits(t *testing.T) {
	salt := mustBytes32(t, "deadbeefcafebabedeadbeefcafebabedeadbeefcafebabedeadbeefcafebabe")
	tinted := TintForwardSalt(salt)

	for i := range salt {
		mask := ^FORWARD_SALT_MAGIC[i]
		if salt[i]&mask != tinted[i]&mask {
			t.Fatalf("non-magic bits changed at byte %d", i)
		}
	}
}

func TestDeriveForwardSalt(t *testing.T) {
	salt := mustBytes32(t, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
	got := DeriveForwardSalt(salt)

	assertHex(t, "DeriveForwardSalt", got[:], "caff6a6a44328f3fb063df12b0cf3fa225a3c6dbdd6acef0f6e619d33890ffbe")
	if !IsForwardedPacket(got) {
		t.Fatal("derived forward salt was not forwarded")
	}
}

func TestUint256ToBytes32(t *testing.T) {
	bz := mustBytes32(t, "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
	x := new(u256.Uint).SetBytes(bz[:])
	got := Uint256ToBytes32(x)

	assertHex(t, "Uint256ToBytes32", got[:], "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
}

func mustBytes32(t *testing.T, h string) [32]byte {
	t.Helper()

	bz, err := hex.DecodeString(h)
	if err != nil {
		t.Fatalf("decode hex: %v", err)
	}
	if len(bz) != 32 {
		t.Fatalf("hex length: got %d want 32", len(bz))
	}

	var out [32]byte
	copy(out[:], bz)
	return out
}
