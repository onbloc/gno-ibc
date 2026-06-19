package core

import (
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// store_istore.gno adapts the proxy-private Store to the IStore interface the
// impl is injected with. Each method routes to the existing client operations,
// keeping the nested *client structure and the chain-param commitment mirror
// private to the proxy. Setters take the borrow-rule (_ int, rlm realm, ...)
// form; the realm token is threaded by the caller and unused here because the
// underlying writes already run in the proxy's ownership context.
var _ IStore = (*Store)(nil)

// AddClient allocates a new client for the light client object and returns its id.
func (s *Store) AddClient(_ int, rlm realm, typ types.ClientType, creator address, lc lightclient.Interface) types.ClientId {
	return s.addClient(typ, creator, lc).id
}

// ClientExists reports whether a client is registered under clientId.
func (s *Store) ClientExists(clientId types.ClientId) bool {
	return s.getClient(clientId) != nil
}

// ClientType returns the registered client type for clientId.
func (s *Store) ClientType(clientId types.ClientId) (types.ClientType, bool) {
	c := s.getClient(clientId)
	if c == nil {
		return "", false
	}
	return c.typ, true
}

// GetLightClient returns the stored light client object for clientId.
func (s *Store) GetLightClient(clientId types.ClientId) (lightclient.Interface, bool) {
	return s.lightClientOf(clientId)
}

// SetLightClient replaces a client's light client object (force-update recovery),
// returning false when the client is unknown.
func (s *Store) SetLightClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) bool {
	c := s.getClient(clientId)
	if c == nil {
		return false
	}
	c.lightClient = lc
	return true
}

// SaveClientState mirrors the client state bytes for queries and counterparty
// proofs, returning false when the client is unknown.
func (s *Store) SaveClientState(_ int, rlm realm, clientId types.ClientId, clientStateBytes []byte) bool {
	c := s.getClient(clientId)
	if c == nil {
		return false
	}
	c.saveState(clientStateBytes)
	return true
}

// SaveConsensusState records the consensus state at height, returning false when
// the client is unknown.
func (s *Store) SaveConsensusState(_ int, rlm realm, clientId types.ClientId, height types.Height, consensusStateBytes []byte) bool {
	c := s.getClient(clientId)
	if c == nil {
		return false
	}
	c.saveConsensusState(height, consensusStateBytes)
	return true
}

// NextConnectionId allocates the next connection id from the sequence.
func (s *Store) NextConnectionId(_ int, rlm realm) types.ConnectionId {
	return s.nextConnectionId()
}

// SaveConnection persists a connection and mirrors its commitment.
func (s *Store) SaveConnection(_ int, rlm realm, connectionId types.ConnectionId, connection types.Connection) {
	s.saveConnection(connectionId, connection)
}

// GetConnection returns the stored connection for connectionId.
func (s *Store) GetConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	return s.getConnection(connectionId)
}
