package core

import (
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

func ChannelOpenInit(cur realm, msg types.MsgChannelOpenInit) types.ChannelId {
	access.AssertCanCall(cross(cur), SelectorChannelOpenInit, cur.Previous().Address())
	return mustGetImpl().ChannelOpenInit(0, cur, msg)
}

func ChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) types.ChannelId {
	access.AssertCanCall(cross(cur), SelectorChannelOpenTry, cur.Previous().Address())
	return mustGetImpl().ChannelOpenTry(0, cur, msg)
}

func ForceChannelOpenTry(cur realm, msg types.MsgChannelOpenTry) types.ChannelId {
	access.AssertCanCall(cross(cur), SelectorForceChannelTry, cur.Previous().Address())
	return mustGetImpl().ForceChannelOpenTry(0, cur, msg)
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
