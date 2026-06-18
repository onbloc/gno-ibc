package e2e

import types "gno.land/p/onbloc/ibc/union/types"

const MockClientType = types.ClientType("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/mock")

type MockLightClient struct{}

func (m *MockLightClient) CreateClient(_ realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "mock-chain"
}

func (m *MockLightClient) UpdateClient(_ realm, clientId types.ClientId, clientMessage []byte) types.ConsensusStateUpdate {
	return types.ConsensusStateUpdate{
		Height:              types.NewHeight(1),
		ClientStateBytes:    clientMessage,
		ConsensusStateBytes: clientMessage,
	}
}

func (m *MockLightClient) VerifyMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte, value []byte) {
}

func (m *MockLightClient) VerifyNonMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte) {
}

func (m *MockLightClient) GetTimestamp(clientId types.ClientId, height types.Height) types.Timestamp {
	return types.Timestamp(1)
}

func (m *MockLightClient) GetLatestHeight(clientId types.ClientId) types.Height {
	return types.NewHeight(1)
}

func (m *MockLightClient) GetStatus(clientId types.ClientId) types.Status {
	return types.StatusActive
}
