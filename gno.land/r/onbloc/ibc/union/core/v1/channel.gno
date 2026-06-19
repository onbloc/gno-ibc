package impl

import (
	"gno.land/p/onbloc/ibc/union/types"
)

// channel.gno: channel handshake and close. Pending migration from the core
// proxy — stubbed so coreV1 satisfies core.ICore.

func (c *coreV1) ChannelOpenInit(_ int, rlm realm, msg types.MsgChannelOpenInit) types.ChannelId {
	panic(errNotMigrated)
}

func (c *coreV1) ChannelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry) types.ChannelId {
	panic(errNotMigrated)
}

func (c *coreV1) ChannelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck) {
	panic(errNotMigrated)
}

func (c *coreV1) ChannelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm) {
	panic(errNotMigrated)
}

func (c *coreV1) ChannelCloseInit(_ int, rlm realm, msg types.MsgChannelCloseInit) {
	panic(errNotMigrated)
}

func (c *coreV1) ChannelCloseConfirm(_ int, rlm realm, msg types.MsgChannelCloseConfirm) {
	panic(errNotMigrated)
}
