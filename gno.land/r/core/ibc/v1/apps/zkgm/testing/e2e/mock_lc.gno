package e2e

import core "gno.land/r/core/ibc/v1/core"

const MockClientType = core.ClientType("zkgm-e2e-mock")

type MockLightClient struct{}

func (m *MockLightClient) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "mock-chain"
}

func (m *MockLightClient) UpdateClient(_ realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	return core.ConsensusStateUpdate{
		Height:              core.Height(1),
		ClientStateBytes:    core.NewBytes(cross, clientMessage),
		ConsensusStateBytes: core.NewBytes(cross, clientMessage),
	}
}

func (m *MockLightClient) Misbehaviour(_ realm, clientId core.ClientId, clientMessage []byte) []byte {
	return nil
}

func (m *MockLightClient) VerifyMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte, value []byte) {
}

func (m *MockLightClient) VerifyNonMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte) {
}

func (m *MockLightClient) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	return core.Timestamp(1)
}

func (m *MockLightClient) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(1)
}

func (m *MockLightClient) GetStatus(clientId core.ClientId) core.Status {
	return core.StatusActive
}
