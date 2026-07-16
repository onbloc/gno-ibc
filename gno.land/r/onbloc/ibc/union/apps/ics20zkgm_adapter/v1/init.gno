package ics20zkgm_adapter

import (
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
)

func init(cur realm) {
	adapter.RegisterImpl(cross(cur), func(store adapter.IStore) adapter.IImpl {
		return NewImpl(store)
	})
}
