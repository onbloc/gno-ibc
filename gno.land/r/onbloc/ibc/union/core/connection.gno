package core

import (
	"chain/runtime"

	"gno.land/p/onbloc/ibc/union/types"
)

func ConnectionOpenInit(cur realm, msg types.MsgConnectionOpenInit) {
	requireAdmin(cur, "ConnectionOpenInit")
	runtime.AssertOriginCall()
	mustGetImpl().ConnectionOpenInit(0, cur, msg)
}

func ConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	requireAdmin(cur, "ConnectionOpenTry")
	runtime.AssertOriginCall()
	mustGetImpl().ConnectionOpenTry(0, cur, msg)
}

func ForceConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	requireAdmin(cur, "ForceConnectionOpenTry")
	runtime.AssertOriginCall()
	mustGetImpl().ForceConnectionOpenTry(0, cur, msg)
}

func ConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	requireAdmin(cur, "ConnectionOpenAck")
	runtime.AssertOriginCall()
	mustGetImpl().ConnectionOpenAck(0, cur, msg)
}

func ForceConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	requireAdmin(cur, "ForceConnectionOpenAck")
	runtime.AssertOriginCall()
	mustGetImpl().ForceConnectionOpenAck(0, cur, msg)
}

func ConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	requireAdmin(cur, "ConnectionOpenConfirm")
	runtime.AssertOriginCall()
	mustGetImpl().ConnectionOpenConfirm(0, cur, msg)
}

func ForceConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	requireAdmin(cur, "ForceConnectionOpenConfirm")
	runtime.AssertOriginCall()
	mustGetImpl().ForceConnectionOpenConfirm(0, cur, msg)
}

func QueryConnection(connectionId types.ConnectionId) string {
	connection, ok := store.getConnection(connectionId)
	if !ok {
		return ""
	}
	bz, err := connection.EncodeABI()
	if err != nil {
		return ""
	}
	return hexString(bz)
}
