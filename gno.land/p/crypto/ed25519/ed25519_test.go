// Test vectors from Go standard library's ed25519 test data:
//   https://github.com/golang/go/blob/master/src/crypto/ed25519/testdata/sign.input.gz
//
// The file is the NACL/SUPERCOP ed25519 test suite used by Go's own TestSignAndVerify.
// Format per line: {seed||pubkey}:{pubkey}:{message_hex}:{signature||message}
// First 3 lines correspond to RFC 8032 §7.1 TEST 1–3:
//   https://www.rfc-editor.org/rfc/rfc8032#section-7.1
//
// seed  = parts[0][:32]  (verified by Go's test: NewKeyFromSeed(seed) == priv[:])
// pubkey = parts[1]
// msg    = parts[2]
// sig    = parts[3][:64]
//
// To regenerate: gunzip -c sign.input.gz | head -3

package ed25519

import (
	goed25519 "crypto/ed25519"
	"encoding/hex"
	"testing"
)

func mustHex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

func TestVerifyKnownVectors(t *testing.T) {
	cases := []struct {
		name   string
		seed   string // sign.input.gz parts[0][:32] — derivable: NewKeyFromSeed(seed).Public() == pubkey
		pubKey string // sign.input.gz parts[1]
		msg    []byte // sign.input.gz parts[2] (decoded)
		sig    string // sign.input.gz parts[3][:128] (64 bytes)
	}{
		{
			// sign.input.gz line 1 — RFC 8032 §7.1 TEST 1 (empty message)
			name:   "line1_empty_msg",
			seed:   "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
			pubKey: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
			msg:    []byte{},
			sig:    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
		},
		{
			// sign.input.gz line 2 — RFC 8032 §7.1 TEST 2 (message: 0x72)
			name:   "line2_one_byte",
			seed:   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
			pubKey: "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
			msg:    []byte{0x72},
			sig:    "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
		},
		{
			// sign.input.gz line 3 — RFC 8032 §7.1 TEST 3 (message: 0xaf82)
			name:   "line3_two_bytes",
			seed:   "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
			pubKey: "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
			msg:    []byte{0xaf, 0x82},
			sig:    "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			seed := mustHex(tc.seed)
			wantPub := mustHex(tc.pubKey)
			sig := mustHex(tc.sig)

			// Verify seed → pubkey derivation matches the file's pubkey field.
			derivedPub := goed25519.NewKeyFromSeed(seed).Public().(goed25519.PublicKey)
			if hex.EncodeToString(derivedPub) != hex.EncodeToString(wantPub) {
				t.Fatalf("seed→pubkey mismatch: got %x, want %x", derivedPub, wantPub)
			}

			if !X_verify(wantPub, tc.msg, sig) {
				t.Fatalf("valid signature rejected")
			}

			// Tampered message must be rejected.
			tampered := append([]byte{0xFF}, tc.msg...)
			if X_verify(wantPub, tampered, sig) {
				t.Fatalf("tampered message should not verify")
			}

			// Bit-flip in signature must be rejected.
			badSig := make([]byte, len(sig))
			copy(badSig, sig)
			badSig[0] ^= 0x01
			if X_verify(wantPub, tc.msg, badSig) {
				t.Fatalf("tampered signature should not verify")
			}

			// Wrong public key must be rejected.
			wrongPub := make([]byte, len(wantPub))
			copy(wrongPub, wantPub)
			wrongPub[0] ^= 0x01
			if X_verify(wrongPub, tc.msg, sig) {
				t.Fatalf("wrong public key should not verify")
			}
		})
	}
}

// TestMalleability mirrors Go stdlib's TestMalleability (same values):
//
//	https://github.com/golang/go/blob/master/src/crypto/ed25519/ed25519_test.go
//
// RFC 8032 §5.1.7 requires s ∈ [0, order); this signature has s ≥ order.
func TestMalleability(t *testing.T) {
	msg := []byte{0x54, 0x65, 0x73, 0x74}
	sig := []byte{
		0x7c, 0x38, 0xe0, 0x26, 0xf2, 0x9e, 0x14, 0xaa, 0xbd, 0x05, 0x9a,
		0x0f, 0x2d, 0xb8, 0xb0, 0xcd, 0x78, 0x30, 0x40, 0x60, 0x9a, 0x8b,
		0xe6, 0x84, 0xdb, 0x12, 0xf8, 0x2a, 0x27, 0x77, 0x4a, 0xb0, 0x67,
		0x65, 0x4b, 0xce, 0x38, 0x32, 0xc2, 0xd7, 0x6f, 0x8f, 0x6f, 0x5d,
		0xaf, 0xc0, 0x8d, 0x93, 0x39, 0xd4, 0xee, 0xf6, 0x76, 0x57, 0x33,
		0x36, 0xa5, 0xc5, 0x1e, 0xb6, 0xf9, 0x46, 0xb3, 0x1d,
	}
	pubKey := []byte{
		0x7d, 0x4d, 0x0e, 0x7f, 0x61, 0x53, 0xa6, 0x9b, 0x62, 0x42, 0xb5,
		0x22, 0xab, 0xbe, 0xe6, 0x85, 0xfd, 0xa4, 0x42, 0x0f, 0x88, 0x34,
		0xb1, 0x08, 0xc3, 0xbd, 0xae, 0x36, 0x9e, 0xf5, 0x49, 0xfa,
	}
	if X_verify(pubKey, msg, sig) {
		t.Fatal("non-canonical signature accepted (s ≥ order)")
	}
}
