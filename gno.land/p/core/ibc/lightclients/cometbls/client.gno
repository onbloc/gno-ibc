package cometbls

import (
	"bytes"
	"errors"

	"gno.land/p/aib/ibc/types"
	"gno.land/p/aib/ics23"
)

const (
	StatusActive  = "Active"
	StatusFrozen  = "Frozen"
	StatusExpired = "Expired"
)

// FrozenHeight is the sentinel height used to freeze a client on misbehaviour.
const FrozenHeight Height = 1

// ValidateInitialize checks the invariants required to initialize a CometBLS client.
func ValidateInitialize(cs ClientState, initial ConsensusState) error {
	if cs.ChainID == "" {
		return errors.New("cometbls: chain ID cannot be empty")
	}
	if cs.TrustingPeriod == 0 {
		return errors.New("cometbls: trusting period must be positive")
	}
	if cs.MaxClockDrift == 0 {
		return errors.New("cometbls: max clock drift must be positive")
	}
	if cs.LatestHeight == 0 {
		return errors.New("cometbls: latest height must be positive")
	}
	if initial.Timestamp == 0 {
		return errors.New("cometbls: initial consensus state timestamp must be positive")
	}
	return nil
}

// Status returns the current status of the client.
//
// latest is the consensus state at cs.LatestHeight.
// A zero Timestamp indicates that no consensus state exists.
func Status(cs ClientState, latest ConsensusState, nowNanos uint64) string {
	if cs.IsFrozen() {
		return StatusFrozen
	}
	if latest.Timestamp == 0 {
		return StatusExpired
	}
	if nowNanos > latest.Timestamp && nowNanos-latest.Timestamp >= cs.TrustingPeriod {
		return StatusExpired
	}
	return StatusActive
}

// ConsensusStateFromHeader builds the ConsensusState stored for a verified Header.
func ConsensusStateFromHeader(lh LightHeader) ConsensusState {
	return ConsensusState{
		Timestamp:          lh.Nanos(),
		Root:               MerkleRoot{Hash: lh.AppHash},
		NextValidatorsHash: lh.NextValidatorsHash,
	}
}

// ConsensusEqualsHeader reports whether a ConsensusState matches a LightHeader.
func ConsensusEqualsHeader(cs ConsensusState, lh LightHeader) bool {
	return cs.Timestamp == lh.Nanos() &&
		cs.NextValidatorsHash == lh.NextValidatorsHash &&
		bytes.Equal(cs.Root.Hash, lh.AppHash)
}

// HeaderHeight returns h.SignedHeader.Height as a CometBLS Height.
func HeaderHeight(h Header) Height {
	return Height(h.SignedHeader.Height)
}

type proofInputs struct {
	specs  []*ics23.ProofSpec
	root   []byte
	proofs []ics23.CommitmentProof
	path   types.MerklePath
}

// VerifyMembership verifies a chained ICS-23 existence proof against a consensus state root.
func VerifyMembership(cs ConsensusState, proofs []ics23.CommitmentProof, path types.MerklePath, value []byte) error {
	if len(value) == 0 {
		return errors.New("cometbls: empty value in membership proof")
	}
	in, err := prepareProofVerify(cs, proofs, path)
	if err != nil {
		return err
	}
	return verifyChainedMembershipProof(in, cloneBytes(value), 0)
}

// VerifyNonMembership verifies a chained ICS-23 non-existence proof against a consensus state root.
func VerifyNonMembership(cs ConsensusState, proofs []ics23.CommitmentProof, path types.MerklePath) error {
	in, err := prepareProofVerify(cs, proofs, path)
	if err != nil {
		return err
	}

	nonexist := in.proofs[0].GetNonexist()
	if nonexist == nil {
		return errors.New("cometbls: first proof must be a non-existence proof")
	}

	subroot, err := nonexist.Calculate()
	if err != nil {
		return errors.New("cometbls: could not calculate root for non-existence proof: " + err.Error())
	}

	key := in.path.KeyPath[len(in.path.KeyPath)-1]
	if err := nonexist.Verify(in.specs[0], subroot, key); err != nil {
		return errors.New("cometbls: non-existence proof verification failed: " + err.Error())
	}

	return verifyChainedMembershipProof(in, subroot, 1)
}

// prepareProofVerify clones inputs across the realm boundary: ics23 reads
// proofs, path bytes, and the root with bytes.Equal, which panics on
// readonly slices.
func prepareProofVerify(cs ConsensusState, proofs []ics23.CommitmentProof, path types.MerklePath) (*proofInputs, error) {
	specs := ics23.GetSDKProofSpecs()
	if len(specs) != len(proofs) {
		return nil, errors.New("cometbls: proof count does not match spec count")
	}
	if len(path.KeyPath) != len(proofs) {
		return nil, errors.New("cometbls: path length does not match proof count")
	}
	if cs.Timestamp == 0 {
		return nil, errors.New("cometbls: consensus state not found at height")
	}
	if len(cs.Root.Hash) == 0 {
		return nil, errors.New("cometbls: empty root hash in consensus state")
	}
	return &proofInputs{
		specs:  specs,
		root:   cloneBytes(cs.Root.Hash),
		proofs: cloneCommitmentProofs(proofs),
		path:   cloneMerklePath(path),
	}, nil
}

// TODO: these boilerplate methods could eliminate by adding type methods line `T.Clone`
// to each type in the `ics23` package. but that package belongs to `gno-realms`,
// it looks like we'd need to add those functions in a separate PR first.
// for now, this seems to be the best approach, should be improved later.

func cloneCommitmentProofs(proofs []ics23.CommitmentProof) []ics23.CommitmentProof {
	out := make([]ics23.CommitmentProof, len(proofs))
	for i, proof := range proofs {
		if exist := proof.GetExist(); exist != nil {
			out[i] = ics23.CommitmentProof_Exist{Exist: cloneExistenceProof(exist)}
			continue
		}
		if nonexist := proof.GetNonexist(); nonexist != nil {
			out[i] = ics23.CommitmentProof_Nonexist{Nonexist: cloneNonExistenceProof(nonexist)}
		}
	}
	return out
}

func cloneExistenceProof(proof *ics23.ExistenceProof) *ics23.ExistenceProof {
	if proof == nil {
		return nil
	}
	out := &ics23.ExistenceProof{
		Key:   cloneBytes(proof.Key),
		Value: cloneBytes(proof.Value),
		Leaf:  cloneLeafOp(proof.Leaf),
		Path:  make([]*ics23.InnerOp, len(proof.Path)),
	}
	for i, inner := range proof.Path {
		out.Path[i] = cloneInnerOp(inner)
	}
	return out
}

func cloneNonExistenceProof(proof *ics23.NonExistenceProof) *ics23.NonExistenceProof {
	if proof == nil {
		return nil
	}
	return &ics23.NonExistenceProof{
		Key:   cloneBytes(proof.Key),
		Left:  cloneExistenceProof(proof.Left),
		Right: cloneExistenceProof(proof.Right),
	}
}

func cloneLeafOp(op *ics23.LeafOp) *ics23.LeafOp {
	if op == nil {
		return nil
	}
	return &ics23.LeafOp{
		Hash:         op.Hash,
		PrehashKey:   op.PrehashKey,
		PrehashValue: op.PrehashValue,
		Length:       op.Length,
		Prefix:       cloneBytes(op.Prefix),
	}
}

func cloneInnerOp(op *ics23.InnerOp) *ics23.InnerOp {
	if op == nil {
		return nil
	}
	return &ics23.InnerOp{
		Hash:   op.Hash,
		Prefix: cloneBytes(op.Prefix),
		Suffix: cloneBytes(op.Suffix),
	}
}

func cloneMerklePath(path types.MerklePath) types.MerklePath {
	out := types.MerklePath{KeyPath: make([][]byte, len(path.KeyPath))}
	for i, key := range path.KeyPath {
		out.KeyPath[i] = cloneBytes(key)
	}
	return out
}

func cloneBytes(b []byte) []byte {
	if b == nil {
		return nil
	}
	out := make([]byte, len(b))
	copy(out, b)
	return out
}

// verifyChainedMembershipProof verifies each existence proof in sequence, threading
// the computed subroot as the value for the next level.
func verifyChainedMembershipProof(in *proofInputs, value []byte, index int) error {
	subroot := value
	for i := index; i < len(in.proofs); i++ {
		exist := in.proofs[i].GetExist()
		if exist == nil {
			return errors.New("cometbls: proof at index must be an existence proof")
		}
		var err error
		subroot, err = exist.Calculate()
		if err != nil {
			return errors.New("cometbls: could not calculate proof root: " + err.Error())
		}
		// keys are ordered highest-to-lowest, proofs lowest-to-highest
		key := in.path.KeyPath[len(in.path.KeyPath)-1-i]
		if err := exist.Verify(in.specs[i], subroot, key, value); err != nil {
			return errors.New("cometbls: membership proof verification failed: " + err.Error())
		}
		value = subroot
	}
	if !bytes.Equal(in.root, subroot) {
		return errors.New("cometbls: proof root does not match consensus state root")
	}
	return nil
}
