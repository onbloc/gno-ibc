package impl

import (
	"gno.land/p/onbloc/ibc/union/types"
)

// connection.gno: connection handshake. Pending migration from the core proxy —
// stubbed so coreV1 satisfies core.ICore.

func (c *coreV1) ConnectionOpenInit(_ int, rlm realm, msg types.MsgConnectionOpenInit) {
	panic(errNotMigrated)
}

func (c *coreV1) ConnectionOpenTry(_ int, rlm realm, msg types.MsgConnectionOpenTry) {
	panic(errNotMigrated)
}

func (c *coreV1) ConnectionOpenAck(_ int, rlm realm, msg types.MsgConnectionOpenAck) {
	panic(errNotMigrated)
}

func (c *coreV1) ConnectionOpenConfirm(_ int, rlm realm, msg types.MsgConnectionOpenConfirm) {
	panic(errNotMigrated)
}
