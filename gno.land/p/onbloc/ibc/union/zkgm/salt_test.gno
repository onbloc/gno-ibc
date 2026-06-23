package zkgm

import (
	"encoding/hex"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestDeriveBatchSalt(t *testing.T) {
	salt1 := mustBytes32(t, "1111111111111111111111111111111111111111111111111111111111111111")
	salt2 := mustBytes32(t, "2222222222222222222222222222222222222222222222222222222222222222")
	vectorSalt := mustBytes32(t, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")

	tests := []struct {
		name        string
		index       *u256.Uint
		salt        [32]byte
		want        string
		compareIdx  *u256.Uint
		compareSalt [32]byte
		wantSame    bool
	}{
		{
			name:  "vector",
			index: u256.NewUint(1),
			salt:  vectorSalt,
			want:  "22270b886c360fef2a5742b5b6c4ea02426060d33d847bee59a6d7b2ef85de17",
		},
		{
			name:        "different index",
			index:       u256.NewUint(1),
			salt:        salt1,
			compareIdx:  u256.NewUint(2),
			compareSalt: salt1,
		},
		{
			name:        "different salt",
			index:       u256.NewUint(1),
			salt:        salt1,
			compareIdx:  u256.NewUint(1),
			compareSalt: salt2,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := DeriveBatchSalt(tc.index, tc.salt)
			if tc.want != "" {
				assertHex(t, tc.name, got[:], tc.want)
			}
			if tc.compareIdx != nil {
				other := DeriveBatchSalt(tc.compareIdx, tc.compareSalt)
				if (got == other) != tc.wantSame {
					t.Fatalf("same result: got %t want %t", got == other, tc.wantSame)
				}
			}
		})
	}
}

func TestTintForwardSalt(t *testing.T) {
	tests := []struct {
		name string
		salt [32]byte
	}{
		{"ok", mustBytes32(t, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")},
		{"idempotent", mustBytes32(t, "fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321")},
		{"preserves data bits", mustBytes32(t, "deadbeefcafebabedeadbeefcafebabedeadbeefcafebabedeadbeefcafebabe")},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tinted := TintForwardSalt(tt.salt)
			if !IsForwardedPacket(tinted) {
				t.Fatal("tinted salt was not forwarded")
			}
			if TintForwardSalt(tinted) != tinted {
				t.Fatal("TintForwardSalt is not idempotent")
			}
			for i := range tt.salt {
				mask := ^FORWARD_SALT_MAGIC[i]
				if tt.salt[i]&mask != tinted[i]&mask {
					t.Fatalf("non-magic bits changed at byte %d", i)
				}
			}
		})
	}
}

func TestIsForwardedPacket(t *testing.T) {
	raw := mustBytes32(t, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
	tests := []struct {
		name string
		salt [32]byte
		want bool
	}{
		{"raw", raw, false},
		{"tinted", TintForwardSalt(raw), true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := IsForwardedPacket(tt.salt); got != tt.want {
				t.Fatalf("got %t want %t", got, tt.want)
			}
		})
	}
}

func TestDeriveForwardSalt(t *testing.T) {
	salt1 := mustBytes32(t, "1111111111111111111111111111111111111111111111111111111111111111")
	salt2 := mustBytes32(t, "2222222222222222222222222222222222222222222222222222222222222222")
	vectorSalt := mustBytes32(t, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")

	tests := []struct {
		name        string
		salt        [32]byte
		want        string
		compareSalt [32]byte
	}{
		{"vector", vectorSalt, "caff6a6a44328f3fb063df12b0cf3fa225a3c6dbdd6acef0f6e619d33890ffbe", [32]byte{}},
		{"different input", salt1, "", salt2},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := DeriveForwardSalt(tt.salt)
			if tt.want != "" {
				assertHex(t, tt.name, got[:], tt.want)
			}
			if !IsForwardedPacket(got) {
				t.Fatal("derived forward salt was not forwarded")
			}
			if tt.compareSalt != [32]byte{} && got == DeriveForwardSalt(tt.compareSalt) {
				t.Fatal("different inputs derived the same forward salt")
			}
		})
	}
}

func TestUint256ToBytes32(t *testing.T) {
	bz := mustBytes32(t, "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
	tests := []struct {
		name string
		x    *u256.Uint
		want string
	}{
		{"bytes32", new(u256.Uint).SetBytes(bz[:]), "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Uint256ToBytes32(tt.x)
			assertHex(t, tt.name, got[:], tt.want)
		})
	}
}

func TestPutUint256BE(t *testing.T) {
	tests := []struct {
		name string
		x    *u256.Uint
		want string
	}{
		{"zero", u256.Zero(), "0000000000000000000000000000000000000000000000000000000000000000"},
		{"one", u256.NewUint(1), "0000000000000000000000000000000000000000000000000000000000000001"},
		{"bytes32", new(u256.Uint).SetBytes(mustHex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")), "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dst := make([]byte, 32)
			putUint256BE(dst, tt.x)
			assertHex(t, tt.name, dst, tt.want)
		})
	}
}

func TestDeriveSenderSalt(t *testing.T) {
	// Vectors generated via tools/zkgm-fixtures/src/bin/derive_sender_salt.rs
	// using alloy-sol-types .abi_encode(), matching Union's Send path.
	cases := []struct {
		name   string
		sender []byte
		salt   string
		want   string
		check  func(t *testing.T)
	}{
		{
			"20-byte sender",
			mustHex("bd1b743615f903a630393f78234b4500fbe5691a"),
			"1111111111111111111111111111111111111111111111111111111111111111",
			"5b496b10c38050e009def5331a8cbf847c5cd1ba1161262ac24f30e75e362e67",
			nil,
		},
		{
			"gno bech32 sender",
			[]byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
			"2222222222222222222222222222222222222222222222222222222222222222",
			"adb3bf0302845394af4413f15786c7167f6a308d1419f4d938474ff024f89e5e",
			nil,
		},
		{
			"empty sender",
			[]byte{},
			"3333333333333333333333333333333333333333333333333333333333333333",
			"7ba1a1735b06fcfe59ddb76919cbdf3afd98e1400354a9633126daa75c5510a2",
			nil,
		},
		{
			name: "deterministic no sequence",
			check: func(t *testing.T) {
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
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.check != nil {
				tc.check(t)
				return
			}
			salt := mustBytes32(t, tc.salt)
			got := DeriveSenderSalt(tc.sender, salt)
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}

func TestDeriveSaltFunctionsDoNotCollide(t *testing.T) {
	tests := []struct {
		name   string
		inputs [][32]byte
	}{
		{
			"distinct derived salt domains",
			[][32]byte{
				mustBytes32(t, "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
				mustBytes32(t, "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"),
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sender := []byte("g1collision")
			for _, salt := range tt.inputs {
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
				if !IsForwardedPacket(forward) {
					t.Fatal("DeriveForwardSalt must produce a forwarded-packet salt")
				}
			}
		})
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
