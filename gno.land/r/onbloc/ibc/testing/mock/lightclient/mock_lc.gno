// Package lightclient provides a permissive light client for IBC smoke and e2e
// tests. Every proof verification succeeds and the client always reports Active,
// so test flows can exercise the core/app realms without real counterparty
// proofs.
package lightclient

import (
	"errors"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/core"
)

const MockClientType = types.ClientType("gno.land/r/onbloc/ibc/testing/mock/lightclient")

type mockLightClient struct{}

func MockClientAddress(cur realm) address {
	return cur.Address()
}

// RegisterMockLightClient registers the mock client implementation under
// MockClientType, unless it is already registered.
func RegisterMockLightClient(cur realm) {
	if !core.HasClient(MockClientType) {
		core.RegisterClient(cross(cur), MockClientType, mockClientImpl)
	}
}

func mockClientImpl(_, _ []byte) (lightclient.Interface, error) {
	return &mockLightClient{}, nil
}

func (m *mockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return nil
}

func (m *mockLightClient) VerifyNonMembership(uint64, []byte, []byte) error {
	return nil
}

func (m *mockLightClient) GetTimestamp() types.Timestamp {
	return types.Timestamp(1)
}

func (m *mockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}

func (m *mockLightClient) GetLatestHeight() uint64 {
	return 1
}

func (m *mockLightClient) GetCounterpartyChainID() string {
	return "mock-chain"
}

func (m *mockLightClient) Status() lightclient.Status {
	return lightclient.Active
}

func (m *mockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{
		Height:              1,
		ClientStateBytes:    header,
		ConsensusStateBytes: header,
	}, nil
}

func (m *mockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errors.New("mock: misbehaviour unsupported")
}
