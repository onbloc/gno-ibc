package v2_locked_recovery

import (
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func init(cur realm) {
	zkgm.RegisterImpl(cross(cur), func(s zkgm.IStore) zkgm.IApp {
		return NewUCS03ZkgmV2LockedRecovery(s)
	})
}
