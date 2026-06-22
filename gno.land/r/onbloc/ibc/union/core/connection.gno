package core

import (
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

func ConnectionOpenInit(cur realm, msg types.MsgConnectionOpenInit) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenInit, cur.Previous().Address())
	mustGetImpl().ConnectionOpenInit(0, cur, msg)
}

func ConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenTry, cur.Previous().Address())
	mustGetImpl().ConnectionOpenTry(0, cur, msg)
}

func ForceConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	access.AssertCanCall(cross(cur), SelectorForceConnectionTry, cur.Previous().Address())
	mustGetImpl().ForceConnectionOpenTry(0, cur, msg)
}

func ConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenAck, cur.Previous().Address())
	mustGetImpl().ConnectionOpenAck(0, cur, msg)
}

func ForceConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	access.AssertCanCall(cross(cur), SelectorForceConnectionAck, cur.Previous().Address())
	mustGetImpl().ForceConnectionOpenAck(0, cur, msg)
}

func ConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	access.AssertCanCall(cross(cur), SelectorConnectionOpenConfirm, cur.Previous().Address())
	mustGetImpl().ConnectionOpenConfirm(0, cur, msg)
}

func ForceConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	access.AssertCanCall(cross(cur), SelectorForceConnectionConfirm, cur.Previous().Address())
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
