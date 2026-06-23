package cometbls

import (
	"errors"
	"strings"
)

// IBC tendermint client sentinel errors
var (
	ErrInvalidChainID                    = errors.New("cometbls: invalid chain-id")
	ErrInvalidHeight                     = errors.New("cometbls: invalid height")
	ErrInvalidProof                      = errors.New("cometbls: invalid proof")
	ErrInvalidConsensus                  = errors.New("cometbls: invalid consensus state")
	ErrInvalidNextValidatorsHash         = errors.New("cometbls: invalid next validators hash")
	ErrInvalidTrustingPeriod             = errors.New("cometbls: invalid trusting period")
	ErrInvalidUnbondingPeriod            = errors.New("cometbls: invalid unbonding period")
	ErrInvalidHeaderHeight               = errors.New("cometbls: invalid header height")
	ErrInvalidMisbehaviour               = errors.New("cometbls: invalid misbehaviour")
	ErrInvalidHeader                     = errors.New("cometbls: invalid header")
	ErrInvalidMaxClockDrift              = errors.New("cometbls: invalid max clock drift")
	ErrProcessedTimeNotFound             = errors.New("cometbls: processed time not found")
	ErrProcessedHeightNotFound           = errors.New("cometbls: processed height not found")
	ErrDelayPeriodNotPassed              = errors.New("cometbls: packet-specified delay period has not been reached")
	ErrTrustingPeriodExpired             = errors.New("cometbls: time since latest trusted state has passed the trusting period")
	ErrUnbondingPeriodExpired            = errors.New("cometbls: time since latest trusted state has passed the unbonding period")
	ErrInvalidProofSpecs                 = errors.New("cometbls: invalid proof specs")
	ErrInvalidValidatorSet               = errors.New("cometbls: invalid validator set")
	ErrInvalidHeaderTimestamp            = errors.New("cometbls: invalid header timestamp")
	ErrInvalidMisbehaviourHeaderSequence = errors.New("cometbls: invalid misbehaviour header sequence")
	ErrMathOverflow                      = errors.New("cometbls: math operation with overflow")
	ErrMisbehaviourNotFound              = errors.New("cometbls: misbehaviour not found")
)

// makeError builds an error from a sentinel base and optional detail strings.
// With no details it returns the sentinel itself (so errors stay comparable);
// otherwise it appends the details to the sentinel's message, joined by ", ".
func makeError(base error, details ...string) error {
	if len(details) == 0 {
		return base
	}

	return errors.New(base.Error() + ", " + strings.Join(details, ", "))
}
