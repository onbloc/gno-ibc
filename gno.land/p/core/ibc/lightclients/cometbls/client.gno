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
// getConsensusState is provided by the realm to read stored consensus states.
//
// Ref: https://github.com/allinbits/gno-realms/blob/master/gno.land/p/aib/ibc/lightclient/tendermint/tendermint.gno
type CometBLSClient struct {
	cs                ClientState
	getConsensusState func(Height) (ConsensusState, bool)
}

// New creates a CometBLSClient.
func New(cs ClientState, getConsensusState func(Height) (ConsensusState, bool)) *CometBLSClient {
	return &CometBLSClient{cs: cs, getConsensusState: getConsensusState}
}

// Status returns the current status of the client.
// Ref: https://github.com/allinbits/gno-realms/blob/master/gno.land/p/aib/ibc/lightclient/tendermint/tendermint.gno
func (c *CometBLSClient) Status(nowNanos uint64) string {
	latest, found := c.getConsensusState(c.cs.LatestHeight)
	return clientStatus(c.cs, latest, found, nowNanos)
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

// clientStatus is the standalone status logic, shared with tests.
func clientStatus(cs ClientState, latestConsensus ConsensusState, found bool, nowNanos uint64) string {
	if cs.IsFrozen() {
		return StatusFrozen
	}
	if !found {
		return StatusExpired
	}
	if nowNanos > latestConsensus.Timestamp && nowNanos-latestConsensus.Timestamp >= cs.TrustingPeriod {
		return StatusExpired
	}
	return StatusActive
}
