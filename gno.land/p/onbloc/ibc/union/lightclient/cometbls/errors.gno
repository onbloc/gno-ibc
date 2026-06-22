package cometbls

import (
	"errors"
	"strings"
)

// IBC tendermint client sentinel errors
var (
	ErrInvalidChainID                    = "invalid chain-id"
	ErrInvalidHeight                     = "invalid height"
	ErrInvalidProof                      = "invalid proof"
	ErrInvalidConsensus                  = "invalid consensus state"
	ErrInvalidNextValidatorsHash         = "invalid next validators hash"
	ErrInvalidTrustingPeriod             = "invalid trusting period"
	ErrInvalidUnbondingPeriod            = "invalid unbonding period"
	ErrInvalidHeaderHeight               = "invalid header height"
	ErrInvalidMisbehaviour               = "invalid misbehaviour"
	ErrInvalidHeader                     = "invalid header"
	ErrInvalidMaxClockDrift              = "invalid max clock drift"
	ErrProcessedTimeNotFound             = "processed time not found"
	ErrProcessedHeightNotFound           = "processed height not found"
	ErrDelayPeriodNotPassed              = "packet-specified delay period has not been reached"
	ErrTrustingPeriodExpired             = "time since latest trusted state has passed the trusting period"
	ErrUnbondingPeriodExpired            = "time since latest trusted state has passed the unbonding period"
	ErrInvalidProofSpecs                 = "invalid proof specs"
	ErrInvalidValidatorSet               = "invalid validator set"
	ErrInvalidHeaderTimestamp            = "invalid header timestamp"
	ErrInvalidMisbehaviourHeaderSequence = "invalid misbehaviour header sequence"
	ErrMathOverflow                      = "math operation with overflow"
	ErrMisbehaviourNotFound              = "misbehaviour not found"
)

func makeError(msgs ...string) error {
	return errors.New(strings.Join(msgs, ", "))
}
