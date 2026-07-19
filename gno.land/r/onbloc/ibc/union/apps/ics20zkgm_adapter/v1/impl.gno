package ics20zkgm_adapter

import (
	z "gno.land/p/onbloc/ibc/union/zkgm"
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
)

type Impl struct {
	store adapter.IStore
}

var _ adapter.IImpl = &Impl{}

func NewImpl(store adapter.IStore) *Impl {
	return &Impl{store: store}
}

// OnZkgm implements adapter.IImpl. Reverse direction: EVM -> AtomOne.
func (i *Impl) OnZkgm(_ int, rlm realm, env z.CallEnv) error {
	panic("ics20zkgm_adapter/v1: OnZkgm not implemented yet")
}

// OnIntentZkgm implements adapter.IImpl.
func (i *Impl) OnIntentZkgm(_ int, rlm realm, env z.IntentCallEnv) error {
	panic("ics20zkgm_adapter/v1: OnIntentZkgm not implemented yet")
}
