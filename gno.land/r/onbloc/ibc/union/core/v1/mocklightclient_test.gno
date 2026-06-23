package impl

import (
	"errors"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// mockLightClient is a configurable lightclient.Interface for the client tests.
// Zero value is an Active client whose verifications succeed.
type mockLightClient struct {
	status             lightclient.Status
	latestHeight       uint64
	createErr          string
	headerErr          string
	membershipErr      string
	nonMembershipErr   string
	timestampErr       string
	timestampAtHt      types.Timestamp
	membershipCalls    int
	nonMembershipCalls int
	update             types.StateUpdate
	creationState      []byte
	creationWrites     map[string][]byte
}

var _ lightclient.Interface = (*mockLightClient)(nil)

func (l *mockLightClient) VerifyMembership(height uint64, key, proof, value []byte) error {
	l.membershipCalls++
	if l.membershipErr != "" {
		return errors.New(l.membershipErr)
	}
	return nil
}

func (l *mockLightClient) VerifyNonMembership(height uint64, key, proof []byte) error {
	l.nonMembershipCalls++
	if l.nonMembershipErr != "" {
		return errors.New(l.nonMembershipErr)
	}
	return nil
}

func (l *mockLightClient) GetTimestamp() types.Timestamp { return 0 }

func (l *mockLightClient) GetTimestampAtHeight(height uint64) (types.Timestamp, error) {
	if l.timestampErr != "" {
		return 0, errors.New(l.timestampErr)
	}
	return l.timestampAtHt, nil
}

func (l *mockLightClient) GetLatestHeight() uint64 { return l.latestHeight }

func (l *mockLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (l *mockLightClient) Status() lightclient.Status {
	if l.status == "" {
		return lightclient.Active
	}
	return l.status
}

func (l *mockLightClient) VerifyHeader(caller address, header []byte, relayer address) (types.StateUpdate, error) {
	if l.headerErr != "" {
		return types.StateUpdate{}, errors.New(l.headerErr)
	}
	return l.update, nil
}

func (l *mockLightClient) VerifyCreation(caller address, relayer address) (types.ClientCreationResult, error) {
	if l.createErr != "" {
		return types.ClientCreationResult{}, errors.New(l.createErr)
	}
	return types.ClientCreationResult{ClientStateBytes: l.creationState, StorageWrites: l.creationWrites}, nil
}

func (l *mockLightClient) Misbehaviour(caller address, misbehaviour []byte, relayer address) ([]byte, error) {
	return nil, nil
}
