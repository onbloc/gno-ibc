package ics20zkgm_adapter

import (
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
)

// mockStore is an in-memory adapter.IStore used by unit tests.
//
// Unlike the production store, which is owned by the proxy realm, mockStore is
// backed by a test-owned map and can be mutated directly by injected test code.
type mockStore struct {
	denomConfigs    map[string]adapter.DenomConfig
	pendingForwards map[string]adapter.PendingForward
}

var _ adapter.IStore = (*mockStore)(nil)

func newMockStore() *mockStore {
	return &mockStore{
		denomConfigs:    map[string]adapter.DenomConfig{},
		pendingForwards: map[string]adapter.PendingForward{},
	}
}

func (m *mockStore) SetDenomConfig(_ int, rlm realm, baseDenom string, cfg adapter.DenomConfig) {
	m.denomConfigs[baseDenom] = cfg
}

func (m *mockStore) RemoveDenomConfig(_ int, rlm realm, baseDenom string) {
	delete(m.denomConfigs, baseDenom)
}

func (m *mockStore) GetDenomConfig(baseDenom string) (adapter.DenomConfig, bool) {
	cfg, ok := m.denomConfigs[baseDenom]
	return cfg, ok
}

func (m *mockStore) HasDenomConfig(baseDenom string) bool {
	_, ok := m.denomConfigs[baseDenom]
	return ok
}

func (m *mockStore) SetPendingForward(_ int, rlm realm, packetHash string, info adapter.PendingForward) {
	m.pendingForwards[packetHash] = info
}

func (m *mockStore) RemovePendingForward(_ int, rlm realm, packetHash string) {
	delete(m.pendingForwards, packetHash)
}

func (m *mockStore) GetPendingForward(packetHash string) (adapter.PendingForward, bool) {
	info, ok := m.pendingForwards[packetHash]
	return info, ok
}
