package core

import (
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

func ChannelOpenInit(cur realm, msg types.MsgChannelOpenInit) {
	access.AssertCanCall(cross(cur), SelectorChannelOpenInit, cur.Previous().Address())
	mustGetImpl().ChannelOpenInit(0, cur, msg)
}

func ChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) {
	access.AssertCanCall(cross(cur), SelectorChannelOpenTry, cur.Previous().Address())
	mustGetImpl().ChannelOpenTry(0, cur, msg)
}

func ForceChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) {
	access.AssertCanCall(cross(cur), SelectorForceChannelTry, cur.Previous().Address())
	mustGetImpl().ForceChannelOpenTry(0, cur, msg)
}

func ChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	access.AssertCanCall(cross(cur), SelectorChannelOpenAck, cur.Previous().Address())
	mustGetImpl().ChannelOpenAck(0, cur, msg)
}

func ForceChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	access.AssertCanCall(cross(cur), SelectorForceChannelAck, cur.Previous().Address())
	mustGetImpl().ForceChannelOpenAck(0, cur, msg)
}

func ChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	access.AssertCanCall(cross(cur), SelectorChannelOpenConfirm, cur.Previous().Address())
	mustGetImpl().ChannelOpenConfirm(0, cur, msg)
}

func ForceChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	access.AssertCanCall(cross(cur), SelectorForceChannelConfirm, cur.Previous().Address())
	mustGetImpl().ForceChannelOpenConfirm(0, cur, msg)
}

func ChannelCloseInit(cur realm, msg types.MsgChannelCloseInit) {
	access.AssertCanCall(cross(cur), SelectorChannelCloseInit, cur.Previous().Address())
	mustGetImpl().ChannelCloseInit(0, cur, msg)
}

func ChannelCloseConfirm(cur realm, msg types.MsgChannelCloseConfirm) {
	access.AssertCanCall(cross(cur), SelectorChannelCloseConfirm, cur.Previous().Address())
	mustGetImpl().ChannelCloseConfirm(0, cur, msg)
}
