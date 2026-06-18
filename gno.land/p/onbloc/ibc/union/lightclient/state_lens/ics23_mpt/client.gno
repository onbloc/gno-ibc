package ics23mpt

import (
	"bytes"
	"crypto/keccak256"
	"errors"

	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/p/onbloc/verifier/evm/storage"
)

// Sentinel errors for the object-form client. Proof-shape errors reuse the
// errors declared in consensus.gno (ErrConsensusStateTooShort,
// ErrInvalidCommitmentKey).
var (
	ErrNoL1Client              = errors.New("ics23mpt: l1 client not configured")
	ErrInvalidHeight           = errors.New("ics23mpt: proof height above latest height")
	ErrConsensusStateNotFound  = errors.New("ics23mpt: consensus state not found at height")
	ErrInvalidCommitmentValue  = errors.New("ics23mpt: commitment value must be 32 bytes")
	ErrStoredValueMismatch     = errors.New("ics23mpt: stored value mismatch")
	ErrMisbehaviourUnsupported = errors.New("ics23mpt: misbehaviour is not supported for state-lens clients")
)

// StateLensIcs23MptLightClient is the stateful object implementing
// lightclient.Interface for the state-lens/ics23/mpt client.
//
// It holds the client state and the L2 consensus states keyed by height,
// mirroring the realm adapter's per-client entry but as a self-contained pure
// object: the adapter routes by clientId into realm storage and delegates L1
// proof verification to core, whereas this object owns its own state and holds
// a direct reference to the L1 light client it depends on.
//
// A state-lens client does not track its own chain directly. It trusts the
// counterparty's opaque L2 consensus blob, proven to exist in the L1 chain's
// state via the L1 light client. Membership of application state is then
// verified against the L2 storage root with EVM MPT storage proofs.
//
// This mirrors Union's StateLensIcs23MptLightClient
// (cosmwasm/lightclient/state-lens-ics23-mpt).
type StateLensIcs23MptLightClient struct {
	clientState            *ClientState
	consensusStateByHeight *bptree.BPTree // height:*ConsensusState
	// l1Client is the light client tracking the settlement (L1) chain. It is
	// used during VerifyHeader to prove that the submitted L2 consensus state is
	// committed in the L1 state, and during Status to mirror the L1 client's
	// liveness. It corresponds to ClientState.L1ClientID, which the realm
	// adapter resolves through core.
	l1Client lightclient.Interface
}

var _ lightclient.Interface = (*StateLensIcs23MptLightClient)(nil)

// NewStateLensIcs23MptLightClient builds a client from the client and consensus
// state and the L1 client it depends on. This mirrors the realm adapter's
// CreateClient path, which seeds the consensus state at L2LatestHeight.
func NewStateLensIcs23MptLightClient(
	clientState *ClientState,
	consensusState *ConsensusState,
	l1Client lightclient.Interface,
) (*StateLensIcs23MptLightClient, error) {
	client := &StateLensIcs23MptLightClient{
		clientState:            clientState,
		consensusStateByHeight: bptree.NewBPTree32(),
		l1Client:               l1Client,
	}

	client.setConsensusState(clientState.L2LatestHeight, consensusState)

	return client, nil
}

// VerifyMembership verifies that key stores value under the L2 storage root at
// the given height using an EVM MPT storage proof. Status gating is the caller's
// responsibility, mirroring the cometbls object form.
func (c *StateLensIcs23MptLightClient) VerifyMembership(height uint64, key []byte, proof []byte, value []byte) error {
	consState, storageProof, err := c.prepareProof(height, key, proof)
	if err != nil {
		return err
	}

	if len(value) != 32 {
		return ErrInvalidCommitmentValue
	}
	if !bytes.Equal(storageProof.Value, value) {
		return ErrStoredValueMismatch
	}

	// storage.VerifyProof only reads the storage root (it hashes the proof key
	// and walks the trie), so the root slice can be passed without copying.
	if err := storage.VerifyProof(consState.StorageRoot, storage.Proof{
		Key:   storageProof.Key,
		Value: storageProof.Value,
		Proof: storageProof.Proof,
	}); err != nil {
		return ufmt.Errorf("ics23mpt: storage membership verification failed: %v", err)
	}

	return nil
}

// VerifyNonMembership verifies the absence of key under the L2 storage root at
// the given height using an EVM MPT absence proof.
func (c *StateLensIcs23MptLightClient) VerifyNonMembership(height uint64, key []byte, proof []byte) error {
	consState, storageProof, err := c.prepareProof(height, key, proof)
	if err != nil {
		return err
	}

	if err := storage.VerifyAbsence(consState.StorageRoot, storage.Proof{
		Key:   storageProof.Key,
		Proof: storageProof.Proof,
	}); err != nil {
		return ufmt.Errorf("ics23mpt: storage non-membership verification failed: %v", err)
	}

	return nil
}

// prepareProof performs the validation shared by VerifyMembership and
// VerifyNonMembership: the proof height must not exceed the latest height, a
// consensus state must exist at the height, the storage proof must decode, and
// its key must match the IBC commitment key derived from path.
func (c *StateLensIcs23MptLightClient) prepareProof(height uint64, key []byte, proof []byte) (*ConsensusState, storage.Proof, error) {
	if height > c.clientState.L2LatestHeight {
		return nil, storage.Proof{}, ErrInvalidHeight
	}

	consState, found := c.getConsensusState(height)
	if !found {
		return nil, storage.Proof{}, ErrConsensusStateNotFound
	}

	storageProof, err := storage.DecodeProof(proof)
	if err != nil {
		return nil, storage.Proof{}, ufmt.Errorf("ics23mpt: invalid storage proof: %v", err)
	}

	if err := VerifyCommitmentKey(key, storageProof.Key); err != nil {
		return nil, storage.Proof{}, err
	}

	return consState, storageProof, nil
}

// VerifyHeader verifies a state-lens header and updates the client. It proves
// that the submitted L2 consensus state is committed in the L1 state at
// L1Height (via the L1 client), then extracts and stores the L2 consensus state
// at L2Height. Mirrors Union's verify_header.
func (c *StateLensIcs23MptLightClient) VerifyHeader(caller address, header []byte, relayer address) (types.StateUpdate, error) {
	if c.l1Client == nil {
		return types.StateUpdate{}, ErrNoL1Client
	}

	h, err := DecodeHeader(header)
	if err != nil {
		return types.StateUpdate{}, ufmt.Errorf("ics23mpt: failed to decode header: %v", err)
	}

	// The L2 consensus state must be committed under the consensus-state path of
	// the L2 client, in the L1 chain's state, as a keccak256 hash.
	consensusPath := types.ConsensusStatePath(types.ClientId(c.clientState.L2ClientID), types.NewHeight(h.L2Height))
	consensusHash := keccak256.Sum256(h.L2ConsensusState)
	if err := c.l1Client.VerifyMembership(h.L1Height, consensusPath[:], h.L2ConsensusStateProof, consensusHash[:]); err != nil {
		return types.StateUpdate{}, ufmt.Errorf("ics23mpt: l1 consensus state membership verification failed: %v", err)
	}

	consState, err := ExtractConsensusState(h.L2ConsensusState, *c.clientState)
	if err != nil {
		return types.StateUpdate{}, err
	}

	return c.updateState(h, &consState), nil
}

// updateState stores the extracted L2 consensus state at L2Height and advances
// the latest height when the header is newer. Mirrors Union's StateUpdate flow.
func (c *StateLensIcs23MptLightClient) updateState(header Header, consState *ConsensusState) types.StateUpdate {
	height := header.L2Height

	c.setConsensusState(height, consState)

	update := types.StateUpdate{Height: height}
	// Mirror the new consensus state bytes so the host (core) can persist them
	// for queries and counterparty proofs. Encoding cannot fail here (roots are
	// fixed 32-byte words), but stay defensive and leave the mirror empty on error.
	if consBytes, err := EncodeConsensusState(*consState); err == nil {
		update.ConsensusStateBytes = consBytes
	}

	if height > c.clientState.L2LatestHeight {
		c.clientState.L2LatestHeight = height
		if csBytes, err := EncodeClientState(*c.clientState); err == nil {
			update.ClientStateBytes = csBytes
		}
	}

	return update
}

// VerifyCreation performs no creation-time state mutation; the state-lens client
// trusts its initial consensus state. Mirrors Union's verify_creation, which
// only emits an event.
func (c *StateLensIcs23MptLightClient) VerifyCreation(caller address, relayer address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

// Misbehaviour is unsupported for state-lens clients, mirroring Union's
// `unimplemented!()` for this client type.
func (c *StateLensIcs23MptLightClient) Misbehaviour(caller address, misbehaviour []byte, relayer address) (types.ClientState, error) {
	return nil, ErrMisbehaviourUnsupported
}

// GetTimestamp returns the timestamp of the consensus state at the latest
// height, or zero when none exists.
func (c *StateLensIcs23MptLightClient) GetTimestamp() types.Timestamp {
	consState, found := c.getConsensusState(c.clientState.L2LatestHeight)
	if !found {
		return 0
	}

	return types.Timestamp(consState.Timestamp)
}

func (c *StateLensIcs23MptLightClient) GetTimestampAtHeight(height uint64) (types.Timestamp, error) {
	consState, found := c.getConsensusState(height)
	if !found {
		return 0, ErrConsensusStateNotFound
	}
	return types.Timestamp(consState.Timestamp), nil
}

func (c *StateLensIcs23MptLightClient) GetLatestHeight() uint64 {
	return c.clientState.L2LatestHeight
}

func (c *StateLensIcs23MptLightClient) GetCounterpartyChainID() string {
	return c.clientState.L2ChainID
}

// Status mirrors the L1 client's status. A state-lens client has no liveness of
// its own: it is only as live as the L1 client it depends on. A missing or
// unknown L1 status is treated as Frozen, matching Union's unwrap_or(Frozen).
func (c *StateLensIcs23MptLightClient) Status() lightclient.Status {
	if c.l1Client == nil {
		return lightclient.Frozen
	}

	switch status := c.l1Client.Status(); status {
	case lightclient.Active, lightclient.Expired, lightclient.Frozen:
		return status
	default:
		return lightclient.Frozen
	}
}

func (c *StateLensIcs23MptLightClient) getConsensusState(height Height) (*ConsensusState, bool) {
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

func (c *StateLensIcs23MptLightClient) setConsensusState(height Height, consState *ConsensusState) {
	c.consensusStateByHeight.Set(heightKey(height), consState)
}

// heightKey renders a height as a fixed-width, lexicographically sortable bptree
// key. ibc-union heights carry a single revision, so the numeric ordering of the
// formatted height matches height ordering.
func heightKey(height Height) string {
	return ufmt.Sprintf("%020d", height)
}
