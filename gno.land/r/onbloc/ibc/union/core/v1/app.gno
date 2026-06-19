package impl

import (
	"gno.land/p/onbloc/ibc/union/app"
)

// app.gno: IBC application registry. Pending migration from the core proxy —
// stubbed so coreV1 satisfies core.ICore.

func (c *coreV1) RegisterApp(_ int, rlm realm, a app.IApp) {
	panic(errNotMigrated)
}
