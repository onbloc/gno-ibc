package cometbls

import (
	"bytes"
	"errors"
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

// New creates a CometBLSClient.
func New(
	cs ClientState,
	getConsensusState func(Height) (ConsensusState, bool),
	setConsensusState func(Height, ConsensusState),
) *CometBLSClient {
	return &CometBLSClient{cs: cs, getConsensusState: getConsensusState, setConsensusState: setConsensusState}
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
