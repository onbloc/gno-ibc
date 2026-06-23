package core

import (
	"chain/runtime"

	"gno.land/p/onbloc/ibc/union/types"
)

func ChannelOpenInit(cur realm, msg types.MsgChannelOpenInit) {
	requireAdmin(cur, "ChannelOpenInit")
	runtime.AssertOriginCall()
	mustGetImpl().ChannelOpenInit(0, cur, msg)
}

func ChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) {
	requireAdmin(cur, "ChannelOpenTry")
	runtime.AssertOriginCall()
	mustGetImpl().ChannelOpenTry(0, cur, msg)
}

func ForceChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) {
	requireAdmin(cur, "ForceChannelOpenTry")
	runtime.AssertOriginCall()
	mustGetImpl().ForceChannelOpenTry(0, cur, msg)
}

func ChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	requireAdmin(cur, "ChannelOpenAck")
	runtime.AssertOriginCall()
	mustGetImpl().ChannelOpenAck(0, cur, msg)
}

func ForceChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	requireAdmin(cur, "ForceChannelOpenAck")
	runtime.AssertOriginCall()
	mustGetImpl().ForceChannelOpenAck(0, cur, msg)
}

func ChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	requireAdmin(cur, "ChannelOpenConfirm")
	runtime.AssertOriginCall()
	mustGetImpl().ChannelOpenConfirm(0, cur, msg)
}

func ForceChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	requireAdmin(cur, "ForceChannelOpenConfirm")
	runtime.AssertOriginCall()
	mustGetImpl().ForceChannelOpenConfirm(0, cur, msg)
}

func ChannelCloseInit(cur realm, msg types.MsgChannelCloseInit) {
	requireAdmin(cur, "ChannelCloseInit")
	runtime.AssertOriginCall()
	mustGetImpl().ChannelCloseInit(0, cur, msg)
}

func ChannelCloseConfirm(cur realm, msg types.MsgChannelCloseConfirm) {
	requireAdmin(cur, "ChannelCloseConfirm")
	runtime.AssertOriginCall()
	mustGetImpl().ChannelCloseConfirm(0, cur, msg)
}
