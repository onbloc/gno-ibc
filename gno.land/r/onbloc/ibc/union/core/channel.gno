package core

import (
	"chain/runtime"

	"gno.land/p/onbloc/ibc/union/types"
)

func ChannelOpenInit(cur realm, msg types.MsgChannelOpenInit) types.ChannelId {
	requireAdmin(cur, "ChannelOpenInit")
	runtime.AssertOriginCall()
	return getImpl().ChannelOpenInit(0, cur, msg)
}

func ChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) types.ChannelId {
	requireAdmin(cur, "ChannelOpenTry")
	runtime.AssertOriginCall()
	return getImpl().ChannelOpenTry(0, cur, msg)
}

func ForceChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) types.ChannelId {
	requireAdmin(cur, "ForceChannelOpenTry")
	runtime.AssertOriginCall()
	return getImpl().ForceChannelOpenTry(0, cur, msg)
}

func ChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	requireAdmin(cur, "ChannelOpenAck")
	runtime.AssertOriginCall()
	getImpl().ChannelOpenAck(0, cur, msg)
}

func ForceChannelOpenAck(cur realm, msg types.MsgChannelOpenAck) {
	requireAdmin(cur, "ForceChannelOpenAck")
	runtime.AssertOriginCall()
	getImpl().ForceChannelOpenAck(0, cur, msg)
}

func ChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	requireAdmin(cur, "ChannelOpenConfirm")
	runtime.AssertOriginCall()
	getImpl().ChannelOpenConfirm(0, cur, msg)
}

func ForceChannelOpenConfirm(cur realm, msg types.MsgChannelOpenConfirm) {
	requireAdmin(cur, "ForceChannelOpenConfirm")
	runtime.AssertOriginCall()
	getImpl().ForceChannelOpenConfirm(0, cur, msg)
}

func ChannelCloseInit(cur realm, msg types.MsgChannelCloseInit) {
	requireAdmin(cur, "ChannelCloseInit")
	runtime.AssertOriginCall()
	getImpl().ChannelCloseInit(0, cur, msg)
}

func ChannelCloseConfirm(cur realm, msg types.MsgChannelCloseConfirm) {
	requireAdmin(cur, "ChannelCloseConfirm")
	runtime.AssertOriginCall()
	getImpl().ChannelCloseConfirm(0, cur, msg)
}

func QueryChannel(channelId types.ChannelId) string {
	entry, found := store.getChannelEntry(channelId)
	if !found {
		return ""
	}
	bz, err := entry.channel.EncodeABI()
	if err != nil {
		return ""
	}
	return hexString(bz)
}

// GetChannel returns the stored channel record for channelId. Apps need this
// to look up the counterparty channel id when constructing packets to send via
// BatchSend (the core no longer auto-derives it from a sender-side helper).
func GetChannel(channelId types.ChannelId) types.Channel {
	return store.getChannel(channelId)
}
