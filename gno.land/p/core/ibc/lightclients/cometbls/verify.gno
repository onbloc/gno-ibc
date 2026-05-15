package cometbls

import (
	"bytes"
	"crypto/cometblszk"
	"errors"
)

// VerifyHeader verifies a CometBLS Header against the client's state and the
// trusted ConsensusState at header.TrustedHeight.
//
// nowNanos is the current block time in nanoseconds since Unix epoch.
func VerifyHeader(cs ClientState, trusted ConsensusState, h Header, nowNanos uint64) error {
	if cs.IsFrozen() {
		return errors.New("cometbls: client is frozen")
	}

	lh := h.SignedHeader

	if uint64(lh.Height) <= h.TrustedHeight {
		return errors.New("cometbls: header height must exceed trusted height")
	}

	if lh.TimeSeconds < 0 || lh.TimeNanos < 0 {
		return errors.New("cometbls: invalid header timestamp")
	}

	headerNanos := lh.Nanos()

	if headerNanos <= trusted.Timestamp {
		return errors.New("cometbls: header timestamp not newer than trusted consensus state")
	}

	if nowNanos > trusted.Timestamp && nowNanos-trusted.Timestamp >= cs.TrustingPeriod {
		return errors.New("cometbls: trusted consensus state has expired")
	}

	if headerNanos > nowNanos+cs.MaxClockDrift {
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
		NextValidatorsHash: lh.NextValidatorsHash[:],
		AppHash:            lh.AppHash,
	}
	return cometblszk.VerifyZKP(cs.ChainID, trusted.NextValidatorsHash[:], zkHeader, h.ZeroKnowledgeProof)
}

// VerifyMisbehaviour verifies that two Headers constitute misbehaviour:
// both pass ZKP verification for the same block height, proving the validator
// set double-signed.
func VerifyMisbehaviour(cs ClientState, trustedA, trustedB ConsensusState, m Misbehaviour, nowNanos uint64) error {
	if cs.IsFrozen() {
		return errors.New("cometbls: client is already frozen")
	}

	if m.HeaderA.SignedHeader.Height != m.HeaderB.SignedHeader.Height {
		return errors.New("cometbls: misbehaviour headers must be at the same height")
	}

	// Headers must differ in content — identical headers at the same height
	// are not misbehaviour (just a duplicate submission).
	if lightHeadersEqual(m.HeaderA.SignedHeader, m.HeaderB.SignedHeader) {
		return errors.New("cometbls: misbehaviour headers are identical")
	}

	if err := VerifyHeader(cs, trustedA, m.HeaderA, nowNanos); err != nil {
		return errors.New("cometbls: header A: " + err.Error())
	}
	if err := VerifyHeader(cs, trustedB, m.HeaderB, nowNanos); err != nil {
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
		a.NextValidatorsHash == b.NextValidatorsHash &&
		bytes.Equal(a.AppHash, b.AppHash)
}
