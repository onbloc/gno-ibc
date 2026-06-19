package impl

import (
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// mockStore is an in-memory core.IStore for the unit tests. The production store
// lives in the proxy realm, so its borrow-rule setters can only be driven from
// that realm; a test in this realm cannot mutate it without tripping the
// readonly-object guard. This mock is backed by plain maps owned by the test
// realm, so the injected impl can read and write it directly.
type mockClient struct {
	typ         types.ClientType
	creator     address
	lc          lightclient.Interface
	clientState []byte
	consensus   map[string][]byte // height.String() -> consensus bytes
}

type mockStore struct {
	seq     uint32
	clients map[uint32]*mockClient
}

var _ core.IStore = (*mockStore)(nil)

func newMockStore() *mockStore {
	return &mockStore{clients: map[uint32]*mockClient{}}
}

// newTestImpl builds a v1 impl bound to a fresh mock store, the way the proxy
// injects its real store at install time.
func newTestImpl() *coreV1 {
	return &coreV1{store: newMockStore()}
}

func (m *mockStore) AddClient(_ int, rlm realm, typ types.ClientType, creator address, lc lightclient.Interface) types.ClientId {
	m.seq++
	id := m.seq
	m.clients[id] = &mockClient{typ: typ, creator: creator, lc: lc, consensus: map[string][]byte{}}
	return types.ClientId(id)
}

func (m *mockStore) ClientExists(clientId types.ClientId) bool {
	_, ok := m.clients[uint32(clientId)]
	return ok
}

func (m *mockStore) ClientType(clientId types.ClientId) (types.ClientType, bool) {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return "", false
	}
	return c.typ, true
}

func (m *mockStore) GetLightClient(clientId types.ClientId) (lightclient.Interface, bool) {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return nil, false
	}
	return c.lc, true
}

func (m *mockStore) SetLightClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) bool {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return false
	}
	c.lc = lc
	return true
}

func (m *mockStore) SaveClientState(_ int, rlm realm, clientId types.ClientId, clientStateBytes []byte) bool {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return false
	}
	c.clientState = clientStateBytes
	return true
}

func (m *mockStore) SaveConsensusState(_ int, rlm realm, clientId types.ClientId, height types.Height, consensusStateBytes []byte) bool {
	c, ok := m.clients[uint32(clientId)]
	if !ok {
		return false
	}
	c.consensus[height.String()] = consensusStateBytes
	return true
}
