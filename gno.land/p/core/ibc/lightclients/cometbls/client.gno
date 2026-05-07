package cometbls

import "errors"

// Client status values, mirroring IBC Go and allinbits/gno-realms lightclient interface.
// Ref: https://github.com/allinbits/gno-realms/blob/master/gno.land/p/aib/ibc/lightclient/lightclient.gno
const (
	StatusActive  = "Active"
	StatusFrozen  = "Frozen"
	StatusExpired = "Expired"
	StatusUnknown = "Unknown"
)

// FrozenHeight is the sentinel height used to freeze a client on misbehaviour.
// Mirrors the tendermint light client convention.
var FrozenHeight = Height{RevisionNumber: 0, RevisionHeight: 1}

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
//
// Ref: https://github.com/allinbits/gno-realms/blob/master/gno.land/p/aib/ibc/lightclient/tendermint/tendermint.gno
type CometBLSClient struct {
	cs                ClientState
	getConsensusState func(Height) (ConsensusState, bool)
	setConsensusState func(Height, ConsensusState)
}

// New creates a CometBLSClient.
func New(
	cs ClientState,
	getConsensusState func(Height) (ConsensusState, bool),
	setConsensusState func(Height, ConsensusState),
) *CometBLSClient {
	return &CometBLSClient{cs: cs, getConsensusState: getConsensusState, setConsensusState: setConsensusState}
}

// Status returns the current status of the client.
// Ref: https://github.com/allinbits/gno-realms/blob/master/gno.land/p/aib/ibc/lightclient/tendermint/tendermint.gno
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

// UpdateStateOnMisbehaviour freezes the client by setting FrozenHeight to {0,1}.
// Must be called after CheckForMisbehaviour returns true.
func (c *CometBLSClient) UpdateStateOnMisbehaviour() {
	c.cs.FrozenHeight = FrozenHeight
}

// UpdateState stores a new ConsensusState derived from the verified Header and
// advances LatestHeight if necessary. Returns the updated height.
// Must be called after VerifyClientMessage succeeds for a Header message.
// Returns nil if msg is not a Header (e.g. Misbehaviour — use UpdateStateOnMisbehaviour instead).
func (c *CometBLSClient) UpdateState(msg ClientMessage) []Height {
	if msg.header == nil {
		return nil
	}
	h := msg.header
	lh := h.SignedHeader
	newHeight := Height{
		RevisionNumber: h.TrustedHeight.RevisionNumber,
		RevisionHeight: uint64(lh.Height),
	}

	// Duplicate update — consensus state at this height already stored.
	if _, found := c.getConsensusState(newHeight); found {
		return []Height{newHeight}
	}

	if newHeight.RevisionHeight > c.cs.LatestHeight.RevisionHeight {
		c.cs.LatestHeight = newHeight
	}

	c.setConsensusState(newHeight, ConsensusState{
		Timestamp:          uint64(lh.TimeSeconds)*1_000_000_000 + uint64(lh.TimeNanos),
		Root:               MerkleRoot{Hash: lh.AppHash},
		NextValidatorsHash: lh.NextValidatorsHash,
	})
	return []Height{newHeight}
}

// CheckForMisbehaviour returns true if the ClientMessage constitutes misbehaviour.
// It assumes VerifyClientMessage has already passed.
//
// For a Misbehaviour message: always true — two ZKP-valid headers at the same
// height with different content is equivocation by definition.
//
// For a Header message: true if a consensus state already exists at the header's
// height with different content, indicating the validator set signed two distinct
// blocks at the same height.
func (c *CometBLSClient) CheckForMisbehaviour(msg ClientMessage) bool {
	if msg.misbehaviour != nil {
		return true
	}
	if msg.header != nil {
		h := msg.header
		existing, found := c.getConsensusState(Height{
			RevisionNumber: h.TrustedHeight.RevisionNumber,
			RevisionHeight: uint64(h.SignedHeader.Height),
		})
		if !found {
			return false
		}
		lh := h.SignedHeader
		headerNanos := uint64(lh.TimeSeconds)*1_000_000_000 + uint64(lh.TimeNanos)
		if existing.Timestamp != headerNanos {
			return true
		}
		if !bytesEqual(existing.NextValidatorsHash, lh.NextValidatorsHash) {
			return true
		}
		if !bytesEqual(existing.Root.Hash, lh.AppHash) {
			return true
		}
	}
	return false
}
