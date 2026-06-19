// Package impl is the v1 implementation of the IBC host logic for the
// gno.land/r/onbloc/ibc/union/core proxy. The proxy keeps the stable identity
// (admin, package address), the Store, and the app registry; this realm holds
// the swappable protocol logic and is injected with the proxy-owned store
// (core.IStore) at install time.
//
// Migration status: the client subsystem is implemented here. Connection,
// channel, and packet handling follow the same shape and are migrated next.
package impl

import (
	core "gno.land/r/onbloc/ibc/union/core"
)

// coreV1 holds the injected proxy state and contains the host logic. State writes
// go through the store's borrow-rule setters: c.store.SetXxx(0, rlm, ...).
type coreV1 struct {
	store core.IStore
}

var _ core.ICore = (*coreV1)(nil)

// errNotMigrated marks an ICore method whose logic still lives on the core proxy.
// Each subsystem replaces its stubs with real impl logic (and moves its tests
// here) as it is migrated; until then these guard against accidental delegation.
const errNotMigrated = "core/v1: subsystem not yet migrated"

// New constructs a fresh v1 impl. The store is injected by the proxy at install
// time via SetStore, so it is nil until installed.
func New() *coreV1 {
	return &coreV1{}
}

// SetStore receives the proxy-owned store at install time (called by
// core.UpdateImpl). Keeping the store private to the proxy means there is no
// public store getter — installation is the only way to obtain it.
func (c *coreV1) SetStore(_ int, rlm realm, store core.IStore) {
	c.store = store
}

// Register installs this impl as the active core host implementation. Gated by
// core.UpdateImpl (admin only).
func Register(cur realm) {
	core.UpdateImpl(cross(cur), New())
}

// cloneBytes returns a fresh copy of b, used to detach caller- or store-owned
// byte slices before persisting or rebuilding records.
func cloneBytes(b []byte) []byte {
	if b == nil {
		return nil
	}
	out := make([]byte, len(b))
	copy(out, b)
	return out
}
