package v2_locked_recovery

import (
	"gno.land/p/nt/bptree/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// recoveredLockedAmounts is this impl's own audit ledger; survives UpdateImpl swaps. See recovery.gno.
var recoveredLockedAmounts *bptree.BPTree

func init(cur realm) {
	recoveredLockedAmounts = bptree.NewBPTree32()

	zkgm.RegisterImpl(cross(cur), func(s zkgm.IStore) zkgm.IApp {
		return NewUCS03ZkgmV2LockedRecovery(s)
	})
}
