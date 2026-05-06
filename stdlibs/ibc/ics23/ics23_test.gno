// Test vectors cross-validated against:
//   cosmos/ics23: https://github.com/cosmos/ics23/blob/master/go/proof_test.go
//
// Proof bytes are protobuf-encoded ics23.CommitmentProof values pre-computed
// from the Go test suite (TendermintSpec single-leaf proofs).

package ics23_test

import (
	"encoding/hex"
	"ibc/ics23"
	"testing"
)

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("invalid hex: %v", err)
	}
	return b
}

// TestVerifyMembershipInvalidInputs checks that malformed inputs return false
// without panicking.
func TestVerifyMembershipInvalidInputs(t *testing.T) {
	if ics23.VerifyMembership("iavl", []byte("root"), []byte("garbage"), []byte("key"), []byte("val")) {
		t.Fatal("malformed proof bytes should return false")
	}
	if ics23.VerifyMembership("iavl", nil, nil, nil, nil) {
		t.Fatal("nil proof should return false")
	}
	if ics23.VerifyMembership("badspec", []byte("root"), []byte("proof"), []byte("key"), []byte("val")) {
		t.Fatal("invalid spec name should return false")
	}
}

// TestVerifyNonMembershipInvalidInputs mirrors the membership checks for the
// non-membership path.
func TestVerifyNonMembershipInvalidInputs(t *testing.T) {
	if ics23.VerifyNonMembership("iavl", []byte("root"), []byte("garbage"), []byte("key")) {
		t.Fatal("malformed proof bytes should return false")
	}
	if ics23.VerifyNonMembership("tendermint", nil, nil, nil) {
		t.Fatal("nil proof should return false")
	}
	if ics23.VerifyNonMembership("badspec", nil, nil, nil) {
		t.Fatal("invalid spec name should return false")
	}
}

// TestVerifyMembershipTendermint verifies a single-leaf Tendermint existence
// proof round-trips: correct key/value passes, wrong value or wrong key fails.
func TestVerifyMembershipTendermint(t *testing.T) {
	root := mustHex(t, "2d6e9a3e3928b84ea41ebc047c06d8b416d5855983a04921bd48adde9c4aa714")
	proof := mustHex(t, "0a150a03666f6f12036261721a090801180120012a0100")

	if !ics23.VerifyMembership("tendermint", root, proof, []byte("foo"), []byte("bar")) {
		t.Fatal("valid Tendermint membership proof should verify")
	}
	if ics23.VerifyMembership("tendermint", root, proof, []byte("foo"), []byte("wrong")) {
		t.Fatal("wrong value should not verify")
	}
	if ics23.VerifyMembership("tendermint", root, proof, []byte("other"), []byte("bar")) {
		t.Fatal("wrong key should not verify")
	}
}

// TestVerifyMembershipMultipleKeys checks that two distinct keys produce
// different roots, each verifying only under their own root (cross-check fails).
func TestVerifyMembershipMultipleKeys(t *testing.T) {
	root1 := mustHex(t, "c2ad13cf4a0dccc614be7f18556d22592c36f7d6e65db7d45bd926c41b3b3468")
	proof1 := mustHex(t, "0a170a05616c69636512033130301a090801180120012a0100")
	root2 := mustHex(t, "231750d12a8936af0c0b40363e80172377031793275a1b279d756c5737d86035")
	proof2 := mustHex(t, "0a150a03626f6212033230301a090801180120012a0100")

	if !ics23.VerifyMembership("tendermint", root1, proof1, []byte("alice"), []byte("100")) {
		t.Fatal("alice proof should verify under root1")
	}
	if !ics23.VerifyMembership("tendermint", root2, proof2, []byte("bob"), []byte("200")) {
		t.Fatal("bob proof should verify under root2")
	}
	if ics23.VerifyMembership("tendermint", root2, proof1, []byte("alice"), []byte("100")) {
		t.Fatal("alice proof should not verify under bob's root")
	}
}

// TestVerifyMembershipWrongRoot checks that a valid proof fails against a wrong root.
func TestVerifyMembershipWrongRoot(t *testing.T) {
	proof := mustHex(t, "0a150a03666f6f12036261721a090801180120012a0100")
	wrongRoot := make([]byte, 32)

	if ics23.VerifyMembership("tendermint", wrongRoot, proof, []byte("foo"), []byte("bar")) {
		t.Fatal("proof should not verify against wrong root")
	}
}
