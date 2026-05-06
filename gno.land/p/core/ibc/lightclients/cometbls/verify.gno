package cometbls

import (
	"bytes"
	"crypto/cometblszk"
	"errors"
)

// verifyHeader verifies a CometBLS Header against the client's state and the
// trusted ConsensusState at header.TrustedHeight.
//
// nowNanos is the current block time in nanoseconds since Unix epoch.
func (c *CometBLSClient) verifyHeader(trusted ConsensusState, h Header, nowNanos uint64) error {
	if c.cs.IsFrozen() {
		return errors.New("cometbls: client is frozen")
	}

	lh := h.SignedHeader

	// New block height must be strictly greater than the trusted height.
	if uint64(lh.Height) <= h.TrustedHeight.RevisionHeight {
		return errors.New("cometbls: header height must exceed trusted height")
	}

	// Header timestamp must be non-negative.
	if lh.TimeSeconds < 0 || lh.TimeNanos < 0 {
		return errors.New("cometbls: invalid header timestamp")
	}

	headerNanos := lh.Nanos()

	// Header must be strictly newer than the trusted consensus state.
	if headerNanos <= trusted.Timestamp {
		return errors.New("cometbls: header timestamp not newer than trusted consensus state")
	}

	// Trusted consensus state must still be within the trusting period.
	if nowNanos > trusted.Timestamp && nowNanos-trusted.Timestamp >= c.cs.TrustingPeriod {
		return errors.New("cometbls: trusted consensus state has expired")
	}

	// Header must not be too far ahead of the local clock (clock drift check).
	if headerNanos > nowNanos+c.cs.MaxClockDrift {
		return errors.New("cometbls: header timestamp exceeds clock drift bound")
	}

	// Verify the Groth16 ZK proof.
	// trustedValidatorsHash is the NextValidatorsHash from the trusted state:
	// at the trusted height H, NextValidatorsHash commits to the validator set
	// that signed the block at H+1 and beyond.
	zkHeader := cometblszk.LightHeader{
		Height:             lh.Height,
		TimeSeconds:        lh.TimeSeconds,
		TimeNanos:          lh.TimeNanos,
		ValidatorsHash:     lh.ValidatorsHash,
		NextValidatorsHash: lh.NextValidatorsHash,
		AppHash:            lh.AppHash,
	}
	return cometblszk.VerifyZKP(c.cs.ChainID, trusted.NextValidatorsHash, zkHeader, h.ZeroKnowledgeProof)
}

// verifyMisbehaviour verifies that two Headers constitute misbehaviour:
// both pass ZKP verification for the same block height, proving the validator
// set double-signed.
func (c *CometBLSClient) verifyMisbehaviour(m Misbehaviour, nowNanos uint64) error {
	if c.cs.IsFrozen() {
		return errors.New("cometbls: client is already frozen")
	}

	// Both conflicting headers must be for the same block height.
	if m.HeaderA.SignedHeader.Height != m.HeaderB.SignedHeader.Height {
		return errors.New("cometbls: misbehaviour headers must be at the same height")
	}

	trustedA, ok := c.getConsensusState(m.HeaderA.TrustedHeight)
	if !ok {
		return errors.New("cometbls: trusted consensus state not found for header A")
	}
	trustedB, ok := c.getConsensusState(m.HeaderB.TrustedHeight)
	if !ok {
		return errors.New("cometbls: trusted consensus state not found for header B")
	}

	// Headers must differ in content — identical headers at the same height
	// are not misbehaviour (just a duplicate submission).
	if lightHeadersEqual(m.HeaderA.SignedHeader, m.HeaderB.SignedHeader) {
		return errors.New("cometbls: misbehaviour headers are identical")
	}

	// Both headers must independently pass ZKP verification.
	if err := c.verifyHeader(trustedA, m.HeaderA, nowNanos); err != nil {
		return errors.New("cometbls: header A: " + err.Error())
	}
	if err := c.verifyHeader(trustedB, m.HeaderB, nowNanos); err != nil {
		return errors.New("cometbls: header B: " + err.Error())
	}

	return nil
}

// lightHeadersEqual reports whether two LightHeaders have identical content.
func lightHeadersEqual(a, b LightHeader) bool {
	if a.Height != b.Height || a.TimeSeconds != b.TimeSeconds || a.TimeNanos != b.TimeNanos {
		return false
	}
	return bytes.Equal(a.ValidatorsHash, b.ValidatorsHash) &&
		bytes.Equal(a.NextValidatorsHash, b.NextValidatorsHash) &&
		bytes.Equal(a.AppHash, b.AppHash)
}
