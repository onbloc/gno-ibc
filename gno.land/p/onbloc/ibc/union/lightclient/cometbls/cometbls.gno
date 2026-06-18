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
}

var _ lightclient.Interface = (*CometblsLightClient)(nil)

// NewCometblsLightClient builds a client from the client and consensus state.
// The membership-key owner is taken from clientState.ContractAddress, so the
// caller (an app/bootstrap realm) only supplies the typed state.
func NewCometblsLightClient(
	clientState *ClientState,
	consensusState *ConsensusState,
) (*CometblsLightClient, error) {
	client := &CometblsLightClient{
		clientState:            clientState,
		consensusStateByHeight: bptree.NewBPTree32(),
	}

	client.setConsensusState(clientState.LatestHeight, consensusState)

	return client, nil
}

func (c *CometblsLightClient) VerifyMembership(height uint64, key []byte, proof []byte, value []byte) error {
	if len(value) == 0 {
		return makeError(ErrInvalidProof, "empty value in membership proof")
	}

	consState, decodedProof, merklePath, err := c.prepareProof(height, key, proof)
	if err != nil {
		return err
	}

	return c.verifyChainedMembershipProof(consState.Root.Hash, decodedProof, merklePath, value, 0)
}

func (c *CometblsLightClient) VerifyNonMembership(height uint64, key []byte, proof []byte) error {
	consState, decodedProof, merklePath, err := c.prepareProof(height, key, proof)
	if err != nil {
		return err
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
	if err := nonexist.Verify(ics23.GetSDKProofSpecs()[0], subroot, key0); err != nil {
		return makeError(ErrInvalidProof, "failed to verify non-membership proof: "+err.Error())
	}

	// Verify the chained membership proof starting from index 1 with value =
	// subroot.
	return c.verifyChainedMembershipProof(consState.Root.Hash, decodedProof, merklePath, subroot, 1)
}

// prepareProof performs the validation shared by VerifyMembership and
// VerifyNonMembership: the proof height must not exceed the latest height, the
// proof must decode, its length must match the SDK proof specs, and a consensus
// state must exist at the height. It returns the consensus state, decoded
// proofs and the membership path for the key.
func (c *CometblsLightClient) prepareProof(height uint64, key []byte, proof []byte) (*ConsensusState, []ics23.CommitmentProof, aibtypes.MerklePath, error) {
	merklePath := aibtypes.MerklePath{}

	if c.clientState.LatestHeight.RevisionHeight < height {
		return nil, nil, merklePath, makeError(
			ErrInvalidHeight,
			ufmt.Sprintf("client state height < proof height (%d < %d), please ensure the client has been updated", c.GetLatestHeight(), height),
		)
	}

	decodedProof, err := DecodeProofs(proof)
	if err != nil {
		return nil, nil, merklePath, makeError(ErrInvalidProof, "failed to decode proof: "+err.Error())
	}

	merklePath = aibtypes.MerklePath{KeyPath: [][]byte{moduleKey, makeStoreKey(c.clientState.ContractAddress, key)}}

	specs := ics23.GetSDKProofSpecs()
	if len(decodedProof) != len(specs) {
		return nil, nil, merklePath, makeError(
			ErrInvalidProof,
			ufmt.Sprintf("length of specs: %d not equal to length of proof: %d", len(specs), len(decodedProof)),
		)
	}

	consState, found := c.getConsensusState(types.NewHeight(height))
	if !found {
		return nil, nil, merklePath, makeError(ErrInvalidConsensus, "please ensure the proof was constructed against a height that exists on the client")
	}

	return consState, decodedProof, merklePath, nil
}

func (c *CometblsLightClient) VerifyHeader(caller address, header []byte, relayer address) (types.StateUpdate, error) {
	tmHeader, err := DecodeHeader(header)
	if err != nil {
		return types.StateUpdate{}, makeError(ErrInvalidHeader, "failed to decode header: "+err.Error())
	}

	if err := tmHeader.ValidateBasic(); err != nil {
		return types.StateUpdate{}, err
	}

	height := tmHeader.GetHeight()
	if _, found := c.getConsensusState(height); found {
		return types.StateUpdate{Height: height.RevisionHeight}, nil
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
	height := header.GetHeight()

	// Duplicate update: a consensus state already exists for this height.
	if _, found := c.getConsensusState(height); found {
		return types.StateUpdate{Height: height.RevisionHeight}
	}

	advancedLatestHeight := height.GT(c.clientState.LatestHeight)
	if advancedLatestHeight {
		c.clientState.LatestHeight = height
	}

	consState := header.ConsensusState()
	c.setConsensusState(height, consState)

	// Mirror the new state bytes so the host (core) can persist them for queries
	// and counterparty proofs. Encoding cannot fail here (hashes are fixed-width),
	// but stay defensive and leave a mirror empty on error.
	update := types.StateUpdate{Height: height.RevisionHeight}
	if consBytes, err := EncodeConsensusState(consState); err == nil {
		update.ConsensusStateBytes = consBytes
	}
	if advancedLatestHeight {
		if csBytes, err := EncodeClientState(c.clientState); err == nil {
			update.ClientStateBytes = csBytes
		}
	}
	return update
}

func (c *CometblsLightClient) GetTimestamp() types.Timestamp {
	lastConsState, found := c.getConsensusState(c.clientState.LatestHeight)
	if !found {
		return 0
	}

	return types.Timestamp(lastConsState.Timestamp)
}

func (c *CometblsLightClient) GetTimestampAtHeight(height uint64) (types.Timestamp, error) {
	consState, found := c.getConsensusState(types.NewHeight(height))
	if !found {
		return 0, makeError(ErrInvalidConsensus, "no consensus state at height")
	}

	return types.Timestamp(consState.Timestamp), nil
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
