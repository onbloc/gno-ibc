// Test vectors from Go standard library's ed25519 test data (sign.input.gz line 2):
//   https://github.com/golang/go/blob/master/src/crypto/ed25519/testdata/sign.input.gz
// Corresponds to RFC 8032 §7.1 TEST 2 (1-byte message 0x72).

package ed25519_test

import (
	"crypto/ed25519"
	"encoding/hex"
	"testing"
)

func TestVerify(t *testing.T) {
	// sign.input.gz line 2: pubkey=3d4017c3..., msg=72, sig=92a009a9...
	pubKey, _ := hex.DecodeString("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
	sig, _ := hex.DecodeString("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
	msg := []byte{0x72}

	if !ed25519.Verify(pubKey, msg, sig) {
		t.Error("valid signature rejected")
	}
	if ed25519.Verify(pubKey, []byte{0x73}, sig) {
		t.Error("wrong message should not verify")
	}
}
