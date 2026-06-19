package e2e

import (
	"errors"

	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
)

const MockClientType = types.ClientType("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/mock")

type MockLightClient struct{}

func (m *MockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return nil
}

func (m *MockLightClient) VerifyNonMembership(uint64, []byte, []byte) error {
	return nil
}

func (m *MockLightClient) GetTimestamp() types.Timestamp {
	return types.Timestamp(1)
}

func (m *MockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}

func (m *MockLightClient) GetLatestHeight() uint64 {
	return 1
}

func (m *MockLightClient) GetCounterpartyChainID() string {
	return "mock-chain"
}

func (m *MockLightClient) Status() lightclient.Status {
	return lightclient.Active
}

func (m *MockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{
		Height:              1,
		ClientStateBytes:    header,
		ConsensusStateBytes: header,
	}, nil
}

func (m *MockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *MockLightClient) Misbehaviour(address, []byte, address) (types.ClientState, error) {
	return nil, errors.New("mock: misbehaviour unsupported")
}
