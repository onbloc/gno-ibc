package impl

import (
	"errors"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// mockLightClient is a configurable lightclient.Interface for the client tests.
// Zero value is an Active client whose verifications succeed.
type mockLightClient struct {
	status           lightclient.Status
	latestHeight     uint64
	createErr        string
	headerErr        string
	membershipErr    string
	nonMembershipErr string
	timestampAtHt    types.Timestamp
	update           types.StateUpdate
	creationWrites   map[string][]byte
	implCalls        int
	implClient       lightclient.Interface
	implCS           []byte
	implCons         []byte
}

var _ lightclient.Interface = (*mockLightClient)(nil)

type mockLensLightClient struct {
	*mockLightClient
	l1ClientId     types.ClientId
	nextL1ClientId types.ClientId
	l1Client       lightclient.Interface
	newLensResult  *mockLensLightClient
}

var _ lightclient.Interface = (*mockLensLightClient)(nil)
var _ lightclient.L1ClientUpdater = (*mockLensLightClient)(nil)

func (l *mockLightClient) ClientImpl(clientStateBytes, consensusStateBytes []byte) (lightclient.Interface, error) {
	l.implCalls++
	l.implCS = clientStateBytes
	l.implCons = consensusStateBytes
	if l.implClient != nil {
		return l.implClient, nil
	}
	return l, nil
}

func (l *mockLensLightClient) ClientImpl(clientStateBytes, consensusStateBytes []byte) (lightclient.Interface, error) {
	l.implCalls++
	l.implCS = clientStateBytes
	l.implCons = consensusStateBytes
	if l.newLensResult != nil {
		return l.newLensResult, nil
	}
	next := &mockLensLightClient{
		mockLightClient: &mockLightClient{latestHeight: l.latestHeight},
		l1ClientId:     l.l1ClientId,
		l1Client:       l.l1Client,
	}
	if l.nextL1ClientId != 0 {
		next.l1ClientId = l.nextL1ClientId
	}
	return next, nil
}

func (l *mockLensLightClient) L1ClientID() types.ClientId {
	return l.l1ClientId
}

func (l *mockLensLightClient) SetL1Client(l1Client lightclient.Interface) {
	l.l1Client = l1Client
}

func (l *mockLightClient) VerifyMembership(height uint64, key, proof, value []byte) error {
	if l.membershipErr != "" {
		return errors.New(l.membershipErr)
	}
	return nil
}

func (l *mockLightClient) VerifyNonMembership(height uint64, key, proof []byte) error {
	if l.nonMembershipErr != "" {
		return errors.New(l.nonMembershipErr)
	}
	return nil
}

func (l *mockLightClient) GetTimestamp() types.Timestamp { return 0 }

func (l *mockLightClient) GetTimestampAtHeight(height uint64) (types.Timestamp, error) {
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
	return types.ClientCreationResult{StorageWrites: l.creationWrites}, nil
}

func (l *mockLightClient) Misbehaviour(caller address, misbehaviour []byte, relayer address) ([]byte, error) {
	return nil, nil
}
