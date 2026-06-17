package cometbls

import (
	"strings"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// https://github.com/cometbft/cometbft/blob/6b567cd510acb6d729869db8621ae93ac79247cf/types/genesis.go#L18-L21
const MaxChainIDLen int = 50

type ClientState struct {
	ChainID         string
	TrustingPeriod  uint64
	UnbondingPeriod uint64
	MaxClockDrift   uint64
	FrozenHeight    types.Height
	LatestHeight    types.Height
}

func NewClientState(
	chainID string,
	trustingPeriod,
	unbondingPeriod uint64,
	maxClockDrift uint64,
	frozenHeight types.Height,
	latestHeight types.Height,
) *ClientState {
	return &ClientState{
		ChainID:         chainID,
		TrustingPeriod:  trustingPeriod,
		UnbondingPeriod: unbondingPeriod,
		MaxClockDrift:   maxClockDrift,
		FrozenHeight:    frozenHeight,
		LatestHeight:    latestHeight,
	}
}

// ClientType is tendermint.
func (ClientState) ClientType() string {
	return ClientType
}

// GetChainID returns the chain-id
func (cs *ClientState) GetChainID() string {
	return cs.ChainID
}

// GetLatestHeight returns latest block height.
func (cs *ClientState) GetLatestHeight() types.Height {
	return cs.LatestHeight
}

// IsExpired returns whether or not the client has passed the trusting period since the last
// update (in which case no headers are considered valid).
func (cs *ClientState) IsExpired(latestTimestamp, now uint64) bool {
	return latestTimestamp+cs.TrustingPeriod <= now
}

// Validate performs a basic validation of the client state fields.
func (cs *ClientState) Validate() error {
	if strings.TrimSpace(cs.ChainID) == "" {
		return makeError(ErrInvalidChainID, "chain id cannot be empty string")
	}

	// NOTE: the value of tmtypes.MaxChainIDLen may change in the future.
	// If this occurs, the code here must account for potential difference
	// between the tendermint version being run by the counterparty chain
	// and the tendermint version used by this light client.
	// https://github.com/cosmos/ibc-go/issues/177
	if len(cs.ChainID) > MaxChainIDLen {
		return makeError(
			ErrInvalidChainID,
			ufmt.Sprintf("chainID is too long; got: %d, max: %d", len(cs.ChainID), MaxChainIDLen),
		)
	}

	if cs.TrustingPeriod <= 0 {
		return makeError(ErrInvalidTrustingPeriod, "trusting period must be greater than zero")
	}

	if cs.UnbondingPeriod <= 0 {
		return makeError(ErrInvalidUnbondingPeriod, "unbonding period must be greater than zero")
	}

	if cs.MaxClockDrift <= 0 {
		return makeError(ErrInvalidMaxClockDrift, "max clock drift must be greater than zero")
	}

	if cs.LatestHeight.RevisionHeight == 0 {
		return makeError(ErrInvalidHeaderHeight, "cometbls client's latest height cannot be zero")
	}

	if cs.TrustingPeriod >= cs.UnbondingPeriod {
		return makeError(
			ErrInvalidTrustingPeriod,
			ufmt.Sprintf("trusting period (%d) should be < unbonding period (%d)", cs.TrustingPeriod, cs.UnbondingPeriod),
		)
	}

	return nil
}

// ZeroCustomFields returns a ClientState that is a copy of the current ClientState
// with all client customizable fields zeroed out
func (cs *ClientState) ZeroCustomFields() *ClientState {
	// copy over all chain-specified fields
	// and leave custom fields empty
	return &ClientState{
		ChainID:         cs.ChainID,
		UnbondingPeriod: cs.UnbondingPeriod,
		LatestHeight:    cs.LatestHeight,
	}
}
