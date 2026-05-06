package ics23

// VerifyMembership verifies an ICS23 existence proof.
// specName must be "iavl" or "tendermint".
// proof is a protobuf-encoded ics23.CommitmentProof.
func VerifyMembership(specName string, root, proof, key, value []byte) bool {
	return verifyMembership(specName, root, proof, key, value)
}

func verifyMembership(specName string, root, proof, key, value []byte) bool // injected

// VerifyNonMembership verifies an ICS23 non-existence proof.
// specName must be "iavl" or "tendermint".
// proof is a protobuf-encoded ics23.CommitmentProof.
func VerifyNonMembership(specName string, root, proof, key []byte) bool {
	return verifyNonMembership(specName, root, proof, key)
}

func verifyNonMembership(specName string, root, proof, key []byte) bool // injected
