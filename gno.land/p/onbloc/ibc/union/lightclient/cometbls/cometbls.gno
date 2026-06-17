package cometbls

import (
	"time"

	aibtypes "gno.land/p/aib/ibc/types"
	"gno.land/p/aib/ics23"
	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// CometblsLightClient is the stateful object implementing lightclient.Interface.
//
// It holds the client state and the consensus states keyed by height, mirroring
// the realm adapter's per-client entry but as a self-contained pure object: the
// adapter routes by clientId into realm storage, whereas this object owns its
// own state and is verified directly against lightclient.Interface.
type CometblsLightClient struct {
	clientState            *ClientState
	consensusStateByHeight *bptree.BPTree // height:*ConsensusState
	ownerAddress           address
}

var _ lightclient.Interface = (*CometblsLightClient)(nil)

// NewCometblsLightClient builds a client from the encoded client and consensus
// state bytes, validating the initialization invariants. This mirrors the realm
// adapter's CreateClient path.
func NewCometblsLightClient(
	clientState *ClientState,
	consensusState *ConsensusState,
	ownerAddress address,
) (*CometblsLightClient, error) {
	client := &CometblsLightClient{
		clientState:            clientState,
		consensusStateByHeight: bptree.NewBPTree32(),
		ownerAddress:           ownerAddress,
	}

	client.setConsensusState(clientState.LatestHeight, consensusState)

	return client, nil
}

func (c *CometblsLightClient) VerifyMembership(height uint64, key []byte, proof []byte, value []byte) error {
	if c.clientState.LatestHeight.RevisionHeight < height {
		return makeError(
			ErrInvalidHeight,
			ufmt.Sprintf("client state height < proof height (%d < %d), please ensure the client has been updated", c.GetLatestHeight(), height),
		)
	}

	if len(value) == 0 {
		return makeError(ErrInvalidProof, "empty value in membership proof")
	}

	decodedProof, err := DecodeProofs(proof)
	if err != nil {
		return makeError(ErrInvalidProof, "failed to decode proof: "+err.Error())
	}

	merklePath := aibtypes.MerklePath{KeyPath: [][]byte{moduleKey, makeStoreKey(c.ownerAddress, key)}}

	ics23ProofSpecs := ics23.GetSDKProofSpecs()

	if len(decodedProof) != len(ics23ProofSpecs) {
		return makeError(
			ErrInvalidProof,
			ufmt.Sprintf("length of specs: %d not equal to length of proof: %d", len(ics23ProofSpecs), len(decodedProof)),
		)
	}

	consState, found := c.getConsensusState(types.NewHeight(height))
	if !found {
		return makeError(ErrInvalidConsensus, "please ensure the proof was constructed against a height that exists on the client")
	}

	return c.verifyChainedMembershipProof(consState.Root.Hash, decodedProof, merklePath, value, 0)
}

func (c *CometblsLightClient) VerifyNonMembership(height uint64, key []byte, proof []byte) error {
	if c.clientState.LatestHeight.RevisionHeight < height {
		return makeError(
			ErrInvalidHeight,
			ufmt.Sprintf("client state height < proof height (%d < %d), please ensure the client has been updated", c.GetLatestHeight(), height),
		)
	}

	decodedProof, err := DecodeProofs(proof)
	if err != nil {
		return makeError(ErrInvalidProof, "failed to decode proof: "+err.Error())
	}

	merklePath := aibtypes.MerklePath{KeyPath: [][]byte{moduleKey, makeStoreKey(c.ownerAddress, key)}}

	ics23ProofSpecs := ics23.GetSDKProofSpecs()

	if len(decodedProof) != len(ics23ProofSpecs) {
		return makeError(
			ErrInvalidProof,
			ufmt.Sprintf("length of specs: %d not equal to length of proof: %d", len(ics23ProofSpecs), len(decodedProof)),
		)
	}

	consState, found := c.getConsensusState(types.NewHeight(height))
	if !found {
		return makeError(ErrInvalidConsensus, "please ensure the proof was constructed against a height that exists on the client")
	}

	// VerifyNonMembership verifies the absence of the key in the lowest subtree
	// and then chains inclusion proofs of all subroots up to the final root.
	nonexist := decodedProof[0].GetNonexist()
	if nonexist == nil {
		return makeError(ErrInvalidProof, "commitment proof must be non-existence proof for verifying non-membership")
	}

	subroot, err := nonexist.Calculate()
	if err != nil {
		return makeError(ErrInvalidProof, "could not calculate root for proof index 0, merkle tree is likely empty: "+err.Error())
	}

	key0 := merklePath.KeyPath[len(merklePath.KeyPath)-1]
	if err := nonexist.Verify(ics23ProofSpecs[0], subroot, key0); err != nil {
		return makeError(ErrInvalidProof, "failed to verify non-membership proof: "+err.Error())
	}

	// Verify the chained membership proof starting from index 1 with value =
	// subroot.
	return c.verifyChainedMembershipProof(consState.Root.Hash, decodedProof, merklePath, subroot, 1)
}

func (c *CometblsLightClient) VerifyHeader(caller address, header []byte, relayer address) (types.StateUpdate, error) {
	tmHeader, err := DecodeHeader(header)
	if err != nil {
		return types.StateUpdate{}, makeError(ErrInvalidHeader, "failed to decode header: "+err.Error())
	}

	if err := tmHeader.ValidateBasic(); err != nil {
		return types.StateUpdate{}, err
	}

	if err := c.verifyHeader(tmHeader, time.Now()); err != nil {
		return types.StateUpdate{}, err
	}

	return c.updateState(tmHeader), nil
}

func (c *CometblsLightClient) VerifyCreation(caller address, relayer address) (types.ClientCreationResult, error) {
	// CometBLS performs no creation-time validation and writes nothing, so the
	// result is empty (mirrors Union's verify_creation).
	return types.ClientCreationResult{}, nil
}

func (c *CometblsLightClient) Misbehaviour(caller address, misbehaviour []byte, relayer address) (types.ClientState, error) {
	m, err := DecodeMisbehaviour(misbehaviour)
	if err != nil {
		return nil, makeError(ErrInvalidMisbehaviour, "failed to decode misbehaviour: "+err.Error())
	}

	if err := m.ValidateBasic(); err != nil {
		return nil, err
	}

	if err := c.verifyMisbehaviour(m, time.Now()); err != nil {
		return nil, err
	}

	// Freeze the client. The frozen height is a sentinel boolean (non-zero).
	c.clientState.FrozenHeight = FrozenHeight

	return c.clientState, nil
}

// updateState creates or updates the consensus state for a verified header and
// advances the latest height when the header is newer. It mirrors Union's
// UpdateState (11-cometbls/update.go).
func (c *CometblsLightClient) updateState(header *Header) types.StateUpdate {
	height := types.NewHeightWithRevision(header.TrustedHeight.RevisionNumber, uint64(header.SignedHeader.Height))

	// Duplicate update: a consensus state already exists for this height.
	if _, found := c.getConsensusState(height); found {
		return types.StateUpdate{Height: height.RevisionHeight}
	}

	if height.GT(c.clientState.LatestHeight) {
		c.clientState.LatestHeight = height
	}

	consState := header.ConsensusState()
	c.setConsensusState(height, consState)

	return types.StateUpdate{Height: height.RevisionHeight}
}

func (c *CometblsLightClient) GetTimestamp() types.Timestamp {
	lastConsState, found := c.getConsensusState(c.clientState.LatestHeight)
	if !found {
		return 0
	}

	return types.Timestamp(lastConsState.Timestamp)
}

func (c *CometblsLightClient) GetLatestHeight() uint64 {
	return c.clientState.LatestHeight.RevisionHeight
}

func (c *CometblsLightClient) GetCounterpartyChainID() string {
	return c.clientState.ChainID
}

func (c *CometblsLightClient) Status() lightclient.Status {
	if !c.clientState.FrozenHeight.IsZero() {
		return lightclient.Frozen
	}

	// get latest consensus state to check for expiry
	lastConsState, found := c.getConsensusState(c.clientState.LatestHeight)
	if !found {
		// if the client state does not have an associated consensus state for its
		// latest height then it must be expired
		return lightclient.Expired
	}

	if c.clientState.IsExpired(lastConsState.Timestamp, uint64(time.Now().UnixNano())) {
		return lightclient.Expired
	}

	return lightclient.Active
}

func (c *CometblsLightClient) hasConsensusState(height types.Height) bool {
	return c.consensusStateByHeight.Has(heightKey(height))
}

func (c *CometblsLightClient) getConsensusState(height types.Height) (*ConsensusState, bool) {
	v, found := c.consensusStateByHeight.Get(heightKey(height))
	if !found {
		return nil, false
	}

	consState, ok := v.(*ConsensusState)
	if !ok {
		return nil, false
	}

	return consState, true
}

func (c *CometblsLightClient) setConsensusState(height types.Height, consState *ConsensusState) {
	c.consensusStateByHeight.Set(heightKey(height), consState)
}

// heightKey renders a height as a fixed-width, lexicographically sortable bptree
// key. CometBLS uses a single revision, so the revision-height ordering matches
// numeric ordering.
func heightKey(height types.Height) string {
	return ufmt.Sprintf("%020d-%020d", height.RevisionNumber, height.RevisionHeight)
}
