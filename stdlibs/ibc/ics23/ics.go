package ics23

import (
	ics23 "github.com/cosmos/ics23/go"
)

// X_verifyMembership verifies an ICS23 existence proof.
//
//   - specName: "iavl" or "tendermint"
//   - root: the commitment root (AppHash)
//   - proof: protobuf-encoded ics23.CommitmentProof
//   - key, value: the key-value pair to prove
func X_verifyMembership(specName string, root, proof, key, value []byte) bool {
	spec := specByName(specName)
	if spec == nil {
		return false
	}
	cp := &ics23.CommitmentProof{}
	if err := cp.Unmarshal(proof); err != nil {
		return false
	}
	return ics23.VerifyMembership(spec, root, cp, key, value)
}

// X_verifyNonMembership verifies an ICS23 non-existence proof.
//
//   - specName: "iavl" or "tendermint"
//   - root: the commitment root (AppHash)
//   - proof: protobuf-encoded ics23.CommitmentProof
//   - key: the key to prove absent
func X_verifyNonMembership(specName string, root, proof, key []byte) bool {
	spec := specByName(specName)
	if spec == nil {
		return false
	}
	cp := &ics23.CommitmentProof{}
	if err := cp.Unmarshal(proof); err != nil {
		return false
	}
	return ics23.VerifyNonMembership(spec, root, cp, key)
}

func specByName(name string) *ics23.ProofSpec {
	switch name {
	case "iavl":
		return ics23.IavlSpec
	case "tendermint":
		return ics23.TendermintSpec
	default:
		return nil
	}
}
