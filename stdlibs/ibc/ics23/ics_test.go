// Test vectors sourced from:
//   cosmos/ics23 proof tests: https://github.com/cosmos/ics23/blob/master/go/proof_test.go
//   cosmos/ics23 testdata: https://github.com/cosmos/ics23/tree/master/testdata
//
// Note: IavlSpec positive tests require the actual IAVL library to generate valid proof
// prefixes (validateIavlOps reads 3 varints from the leaf prefix). The positive
// round-trip tests below use TendermintSpec, which accepts the simple 0x00 prefix.

package ics23

import (
	"testing"

	ics23 "github.com/cosmos/ics23/go"
)

// TestSpecByName verifies the spec lookup used internally by both exported functions.
func TestSpecByName(t *testing.T) {
	if specByName("iavl") == nil {
		t.Fatal("iavl spec should not be nil")
	}
	if specByName("tendermint") == nil {
		t.Fatal("tendermint spec should not be nil")
	}
	if specByName("unknown") != nil {
		t.Fatal("unknown spec name should return nil")
	}
	if specByName("") != nil {
		t.Fatal("empty spec name should return nil")
	}
}

// TestVerifyMembershipInvalidInputs checks that malformed / wrong inputs return false.
func TestVerifyMembershipInvalidInputs(t *testing.T) {
	if X_verifyMembership("iavl", []byte("root"), []byte("garbage"), []byte("key"), []byte("val")) {
		t.Fatal("malformed proof bytes should return false")
	}
	if X_verifyMembership("iavl", nil, nil, nil, nil) {
		t.Fatal("nil proof should return false")
	}
	if X_verifyMembership("badspec", []byte("root"), []byte("proof"), []byte("key"), []byte("val")) {
		t.Fatal("invalid spec name should return false")
	}
}

// TestVerifyNonMembershipInvalidInputs mirrors the membership checks for the
// non-membership path.
func TestVerifyNonMembershipInvalidInputs(t *testing.T) {
	if X_verifyNonMembership("iavl", []byte("root"), []byte("garbage"), []byte("key")) {
		t.Fatal("malformed proof bytes should return false")
	}
	if X_verifyNonMembership("tendermint", nil, nil, nil) {
		t.Fatal("nil proof should return false")
	}
	if X_verifyNonMembership("badspec", nil, nil, nil) {
		t.Fatal("invalid spec name should return false")
	}
}

// buildTendermintProof creates a valid single-leaf Tendermint commitment proof
// for the given key/value pair, along with its computed root.
func buildTendermintProof(key, value []byte) (root []byte, proofBytes []byte, err error) {
	ep := &ics23.ExistenceProof{
		Key:   key,
		Value: value,
		Leaf:  ics23.TendermintSpec.LeafSpec,
		Path:  nil,
	}
	root, err = ep.Calculate()
	if err != nil {
		return nil, nil, err
	}
	cp := &ics23.CommitmentProof{Proof: &ics23.CommitmentProof_Exist{Exist: ep}}
	proofBytes, err = cp.Marshal()
	return root, proofBytes, err
}

// TestVerifyMembershipTendermint verifies a single-leaf Tendermint proof round-trips.
func TestVerifyMembershipTendermint(t *testing.T) {
	key := []byte("foo")
	value := []byte("bar")

	root, proofBytes, err := buildTendermintProof(key, value)
	if err != nil {
		t.Fatalf("buildTendermintProof: %v", err)
	}

	if !X_verifyMembership("tendermint", root, proofBytes, key, value) {
		t.Fatal("valid Tendermint membership proof should verify")
	}
	if X_verifyMembership("tendermint", root, proofBytes, key, []byte("wrong")) {
		t.Fatal("wrong value should not verify")
	}
	if X_verifyMembership("tendermint", root, proofBytes, []byte("other"), value) {
		t.Fatal("wrong key should not verify")
	}
}

// TestVerifyMembershipMultipleKeys checks that two distinct keys produce
// different roots, each verifying only under their own root.
func TestVerifyMembershipMultipleKeys(t *testing.T) {
	root1, proof1, err := buildTendermintProof([]byte("alice"), []byte("100"))
	if err != nil {
		t.Fatal(err)
	}
	root2, proof2, err := buildTendermintProof([]byte("bob"), []byte("200"))
	if err != nil {
		t.Fatal(err)
	}

	if !X_verifyMembership("tendermint", root1, proof1, []byte("alice"), []byte("100")) {
		t.Fatal("alice proof should verify under root1")
	}
	if !X_verifyMembership("tendermint", root2, proof2, []byte("bob"), []byte("200")) {
		t.Fatal("bob proof should verify under root2")
	}
	// Cross-check: alice's proof must NOT verify under bob's root.
	if X_verifyMembership("tendermint", root2, proof1, []byte("alice"), []byte("100")) {
		t.Fatal("alice proof should not verify under root2")
	}
}

// TestVerifyMembershipWrongRoot checks that a valid proof fails against a wrong root.
func TestVerifyMembershipWrongRoot(t *testing.T) {
	_, proofBytes, err := buildTendermintProof([]byte("key"), []byte("value"))
	if err != nil {
		t.Fatal(err)
	}
	wrongRoot := make([]byte, 32)
	if X_verifyMembership("tendermint", wrongRoot, proofBytes, []byte("key"), []byte("value")) {
		t.Fatal("proof should not verify against wrong root")
	}
}
