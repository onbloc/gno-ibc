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

// ClientMessage wraps either a Header or Misbehaviour for VerifyClientMessage.
type ClientMessage struct {
	header       *Header
	misbehaviour *Misbehaviour
}

// NewHeaderMessage wraps a Header as a ClientMessage.
func NewHeaderMessage(h Header) ClientMessage {
	return ClientMessage{header: &h}
}

// NewMisbehaviourMessage wraps a Misbehaviour as a ClientMessage.
func NewMisbehaviourMessage(m Misbehaviour) ClientMessage {
	return ClientMessage{misbehaviour: &m}
}

// CometBLSClient is the CometBLS IBC light client.
// getConsensusState and setConsensusState are provided by the realm to
// read and write stored consensus states.
type CometBLSClient struct {
	cs                ClientState
	getConsensusState func(Height) (ConsensusState, bool)
	setConsensusState func(Height, ConsensusState)
}

// New creates a CometBLSClient with realm-provided storage callbacks.
// Call Initialize before using any other method.
func New(
	getConsensusState func(Height) (ConsensusState, bool),
	setConsensusState func(Height, ConsensusState),
) *CometBLSClient {
	return &CometBLSClient{getConsensusState: getConsensusState, setConsensusState: setConsensusState}
}

// Initialize sets the client state and stores the initial consensus state.
// Must be called once upon client creation before any other method.
func (c *CometBLSClient) Initialize(cs ClientState, initial ConsensusState) error {
	if err := validateInitialize(cs, initial); err != nil {
		return err
	}
	c.cs = cs
	c.setConsensusState(cs.LatestHeight, initial)
	return nil
}

func validateInitialize(cs ClientState, initial ConsensusState) error {
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
	if len(initial.NextValidatorsHash) == 0 {
		return errors.New("cometbls: initial consensus state next validators hash cannot be empty")
	}
	return nil
}

// Status returns the current status of the client.
func (c *CometBLSClient) Status(nowNanos uint64) string {
	if c.cs.IsFrozen() {
		return StatusFrozen
	}
	latest, found := c.getConsensusState(c.cs.LatestHeight)
	if !found {
		return StatusExpired
	}
	if nowNanos > latest.Timestamp && nowNanos-latest.Timestamp >= c.cs.TrustingPeriod {
		return StatusExpired
	}
	return StatusActive
}

// VerifyClientMessage verifies a Header or Misbehaviour against the current client state.
func (c *CometBLSClient) VerifyClientMessage(msg ClientMessage, nowNanos uint64) error {
	if msg.header != nil {
		trusted, ok := c.getConsensusState(msg.header.TrustedHeight)
		if !ok {
			return errors.New("cometbls: trusted consensus state not found")
		}
		return c.verifyHeader(trusted, *msg.header, nowNanos)
	}
	if msg.misbehaviour != nil {
		return c.verifyMisbehaviour(*msg.misbehaviour, nowNanos)
	}
	return errors.New("cometbls: empty client message")
}

// UpdateStateOnMisbehaviour freezes the client by setting FrozenHeight to 1.
func (c *CometBLSClient) UpdateStateOnMisbehaviour() {
	c.cs.FrozenHeight = FrozenHeight
}

// UpdateState stores a new ConsensusState derived from the verified Header and
// advances LatestHeight if necessary.
func (c *CometBLSClient) UpdateState(msg ClientMessage) []Height {
	if msg.header == nil {
		return nil
	}

	h := msg.header
	newHeight := headerHeight(*h)

	if _, found := c.getConsensusState(newHeight); found {
		return []Height{newHeight}
	}

	if newHeight > c.cs.LatestHeight {
		c.cs.LatestHeight = newHeight
	}

	c.setConsensusState(newHeight, consensusStateFromHeader(h.SignedHeader))
	return []Height{newHeight}
}

// CheckForMisbehaviour returns true if the ClientMessage constitutes misbehaviour.
func (c *CometBLSClient) CheckForMisbehaviour(msg ClientMessage) bool {
	if msg.misbehaviour != nil {
		return true
	}
	if msg.header == nil {
		return false
	}
	h := msg.header
	existing, found := c.getConsensusState(headerHeight(*h))
	if !found {
		return false
	}
	return !consensusEqualsHeader(existing, h.SignedHeader)
}

func (c *CometBLSClient) LatestHeight() Height {
	return c.cs.LatestHeight
}

func (c *CometBLSClient) TimestampAtHeight(h Height) (uint64, bool) {
	cs, found := c.getConsensusState(h)
	if !found {
		return 0, false
	}
	return cs.Timestamp, true
}

func headerHeight(h Header) Height {
	return Height(h.SignedHeader.Height)
}

func consensusStateFromHeader(lh LightHeader) ConsensusState {
	return ConsensusState{
		Timestamp:          lh.Nanos(),
		Root:               MerkleRoot{Hash: lh.AppHash},
		NextValidatorsHash: lh.NextValidatorsHash,
	}
}

func consensusEqualsHeader(cs ConsensusState, lh LightHeader) bool {
	return cs.Timestamp == lh.Nanos() &&
		bytes.Equal(cs.NextValidatorsHash, lh.NextValidatorsHash) &&
		bytes.Equal(cs.Root.Hash, lh.AppHash)
}

// RecoverClient copies the substitute's latest consensus state into the subject,
// adopts its ChainID, LatestHeight and TrustingPeriod, and un-freezes the subject.
func (c *CometBLSClient) RecoverClient(substitute *CometBLSClient) error {
	if substitute == nil {
		return errors.New("cometbls: substitute client must not be nil")
	}
	if c.cs.MaxClockDrift != substitute.cs.MaxClockDrift {
		return errors.New("cometbls: subject and substitute client states differ on MaxClockDrift")
	}
	subLatest := substitute.cs.LatestHeight
	subConsState, found := substitute.getConsensusState(subLatest)
	if !found {
		return errors.New("cometbls: substitute consensus state not found at latest height")
	}
	c.cs.ChainID = substitute.cs.ChainID
	c.cs.LatestHeight = subLatest
	c.cs.TrustingPeriod = substitute.cs.TrustingPeriod
	c.cs.ContractAddress = substitute.cs.ContractAddress
	c.cs.FrozenHeight = 0
	c.setConsensusState(subLatest, subConsState)
	return nil
}

// VerifyMembership verifies a chained ICS-23 existence proof against the
// consensus state root at height. path and proofs must have the same length.
func (c *CometBLSClient) VerifyMembership(height Height, proofs []ics23.CommitmentProof, path types.MerklePath, value []byte) error {
	if c.cs.IsFrozen() {
		return errors.New("cometbls: client is frozen")
	}
	if len(value) == 0 {
		return errors.New("cometbls: empty value in membership proof")
	}

	specs := ics23.GetSDKProofSpecs()
	if len(specs) != len(proofs) {
		return errors.New("cometbls: proof count does not match spec count")
	}
	if len(path.KeyPath) != len(proofs) {
		return errors.New("cometbls: path length does not match proof count")
	}

	cs, found := c.getConsensusState(height)
	if !found {
		return errors.New("cometbls: consensus state not found at height")
	}
	if len(cs.Root.Hash) == 0 {
		return errors.New("cometbls: empty root hash in consensus state")
	}

	return verifyChainedMembershipProof(cs.Root.Hash, specs, proofs, path, value, 0)
}

// VerifyNonMembership verifies a chained ICS-23 non-existence proof against
// the consensus state root at height.
func (c *CometBLSClient) VerifyNonMembership(height Height, proofs []ics23.CommitmentProof, path types.MerklePath) error {
	if c.cs.IsFrozen() {
		return errors.New("cometbls: client is frozen")
	}

	specs := ics23.GetSDKProofSpecs()
	if len(specs) != len(proofs) {
		return errors.New("cometbls: proof count does not match spec count")
	}

	if len(path.KeyPath) != len(proofs) {
		return errors.New("cometbls: path length does not match proof count")
	}

	cs, found := c.getConsensusState(height)
	if !found {
		return errors.New("cometbls: consensus state not found at height")
	}
	if len(cs.Root.Hash) == 0 {
		return errors.New("cometbls: empty root hash in consensus state")
	}

	nonexist := proofs[0].GetNonexist()
	if nonexist == nil {
		return errors.New("cometbls: first proof must be a non-existence proof")
	}

	subroot, err := nonexist.Calculate()
	if err != nil {
		return errors.New("cometbls: could not calculate root for non-existence proof: " + err.Error())
	}

	key := path.KeyPath[len(path.KeyPath)-1]
	if err := nonexist.Verify(specs[0], subroot, key); err != nil {
		return errors.New("cometbls: non-existence proof verification failed: " + err.Error())
	}

	return verifyChainedMembershipProof(cs.Root.Hash, specs, proofs, path, subroot, 1)
}

// verifyChainedMembershipProof verifies each existence proof in sequence, threading
// the computed subroot as the value for the next level.
// index is the proof index to start from (1 for non-membership to skip the
// already-verified non-existence proof at index 0).
func verifyChainedMembershipProof(root []byte, specs []*ics23.ProofSpec, proofs []ics23.CommitmentProof, keys types.MerklePath, value []byte, index int) error {
	subroot := value
	for i := index; i < len(proofs); i++ {
		exist := proofs[i].GetExist()
		if exist == nil {
			return errors.New("cometbls: proof at index must be an existence proof")
		}
		var err error
		subroot, err = exist.Calculate()
		if err != nil {
			return errors.New("cometbls: could not calculate proof root: " + err.Error())
		}
		// keys are ordered highest-to-lowest, proofs lowest-to-highest
		key := keys.KeyPath[len(keys.KeyPath)-1-i]
		if err := exist.Verify(specs[i], subroot, key, value); err != nil {
			return errors.New("cometbls: membership proof verification failed: " + err.Error())
		}
		value = subroot
	}
	if !bytes.Equal(root, subroot) {
		return errors.New("cometbls: proof root does not match consensus state root")
	}
	return nil
}

// VerifyUpgradeAndUpdateState decodes and validates the upgraded ClientState and
// ConsensusState (ABI-encoded), then applies the upgrade.
func (c *CometBLSClient) VerifyUpgradeAndUpdateState(newClient, newConsState, _, _ []byte) error {
	upgradedCS, err := DecodeClientState(newClient)
	if err != nil {
		return errors.New("cometbls: failed to decode upgraded client state: " + err.Error())
	}
	upgradedConsState, err := DecodeConsensusState(newConsState)
	if err != nil {
		return errors.New("cometbls: failed to decode upgraded consensus state: " + err.Error())
	}
	if upgradedCS.IsFrozen() {
		return errors.New("cometbls: upgraded client state must not be frozen")
	}
	if upgradedCS.LatestHeight <= c.cs.LatestHeight {
		return errors.New("cometbls: upgraded client height must be greater than current height")
	}
	if upgradedConsState.Timestamp == 0 {
		return errors.New("cometbls: upgraded consensus state must have a non-zero timestamp")
	}
	c.cs = upgradedCS
	c.setConsensusState(upgradedCS.LatestHeight, upgradedConsState)
	return nil
}
