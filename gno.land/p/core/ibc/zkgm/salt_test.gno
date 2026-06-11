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

func TestDeriveSenderSaltMatchesUnion(t *testing.T) {
	// Vectors generated via tools/zkgm-fixtures/src/bin/derive_sender_salt.rs
	// using alloy-sol-types .abi_encode(), matching Union's Send path.
	sender1 := mustHex("bd1b743615f903a630393f78234b4500fbe5691a")
	salt1 := mustBytes32(t, "1111111111111111111111111111111111111111111111111111111111111111")
	got1 := DeriveSenderSalt(sender1, salt1)
	assertHex(t, "20-byte sender", got1[:], "5b496b10c38050e009def5331a8cbf847c5cd1ba1161262ac24f30e75e362e67")

	sender2 := []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	salt2 := mustBytes32(t, "2222222222222222222222222222222222222222222222222222222222222222")
	got2 := DeriveSenderSalt(sender2, salt2)
	assertHex(t, "gno bech32 sender", got2[:], "adb3bf0302845394af4413f15786c7167f6a308d1419f4d938474ff024f89e5e")
}

func TestDeriveSenderSaltEmptySender(t *testing.T) {
	salt := mustBytes32(t, "3333333333333333333333333333333333333333333333333333333333333333")
	got := DeriveSenderSalt([]byte{}, salt)

	assertHex(t, "empty sender", got[:], "7ba1a1735b06fcfe59ddb76919cbdf3afd98e1400354a9633126daa75c5510a2")
}

func TestDeriveSenderSaltDeterministicNoSequence(t *testing.T) {
	sender := []byte("g1dedupcaller")
	salt := mustBytes32(t, "4444444444444444444444444444444444444444444444444444444444444444")
	otherSalt := mustBytes32(t, "4545454545454545454545454545454545454545454545454545454545454545")

	first := DeriveSenderSalt(sender, salt)
	second := DeriveSenderSalt(sender, salt)
	other := DeriveSenderSalt(sender, otherSalt)

	if first != second {
		t.Fatal("same sender and salt derived different values")
	}
	if first == other {
		t.Fatal("different salt derived the same value")
	}
}

func TestDeriveBatchSaltDifferentIndexProducesDifferentSalt(t *testing.T) {
	salt := mustBytes32(t, "1111111111111111111111111111111111111111111111111111111111111111")
	a := DeriveBatchSalt(u256.NewUint(1), salt)
	b := DeriveBatchSalt(u256.NewUint(2), salt)
	if a == b {
		t.Fatal("different indices derived the same batch salt")
	}
}

func TestDeriveBatchSaltDifferentSaltProducesDifferentResult(t *testing.T) {
	salt1 := mustBytes32(t, "1111111111111111111111111111111111111111111111111111111111111111")
	salt2 := mustBytes32(t, "2222222222222222222222222222222222222222222222222222222222222222")
	a := DeriveBatchSalt(u256.NewUint(1), salt1)
	b := DeriveBatchSalt(u256.NewUint(1), salt2)
	if a == b {
		t.Fatal("different salts derived the same batch salt")
	}
}

func TestDeriveForwardSaltDifferentInputProducesDifferentResult(t *testing.T) {
	salt1 := mustBytes32(t, "1111111111111111111111111111111111111111111111111111111111111111")
	salt2 := mustBytes32(t, "2222222222222222222222222222222222222222222222222222222222222222")
	a := DeriveForwardSalt(salt1)
	b := DeriveForwardSalt(salt2)
	if a == b {
		t.Fatal("different inputs derived the same forward salt")
	}
}

func TestDeriveSaltFunctionsDoNotCollide(t *testing.T) {
	inputs := [][32]byte{
		mustBytes32(t, "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
		mustBytes32(t, "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"),
	}
	sender := []byte("g1collision")
	for _, salt := range inputs {
		batch := DeriveBatchSalt(u256.NewUint(1), salt)
		forward := DeriveForwardSalt(salt)
		sender_ := DeriveSenderSalt(sender, salt)
		if batch == forward {
			t.Fatal("DeriveBatchSalt and DeriveForwardSalt collide")
		}
		if batch == sender_ {
			t.Fatal("DeriveBatchSalt and DeriveSenderSalt collide")
		}
		if forward == sender_ {
			t.Fatal("DeriveForwardSalt and DeriveSenderSalt collide")
		}
		if IsForwardedPacket(batch) {
			t.Fatal("DeriveBatchSalt must not produce a forwarded-packet salt")
		}
		if !IsForwardedPacket(forward) {
			t.Fatal("DeriveForwardSalt must produce a forwarded-packet salt")
		}
	}
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
