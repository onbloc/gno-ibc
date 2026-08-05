package core

import (
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

func ConnectionOpenInit(cur realm, msg types.MsgConnectionOpenInit) {
	access.AssertCanCall(0, cur, SelectorConnectionOpenInit)
	mustGetImpl().ConnectionOpenInit(0, cur, msg)
}

func ConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	access.AssertCanCall(0, cur, SelectorConnectionOpenTry)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().ConnectionOpenTry(0, cur, msg)
}

func ForceConnectionOpenTry(cur realm, msg types.MsgConnectionOpenTry) {
	access.AssertCanCall(0, cur, SelectorForceConnectionTry)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().ForceConnectionOpenTry(0, cur, msg)
}

func ConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	access.AssertCanCall(0, cur, SelectorConnectionOpenAck)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().ConnectionOpenAck(0, cur, msg)
}

func ForceConnectionOpenAck(cur realm, msg types.MsgConnectionOpenAck) {
	access.AssertCanCall(0, cur, SelectorForceConnectionAck)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().ForceConnectionOpenAck(0, cur, msg)
}

func ConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	access.AssertCanCall(0, cur, SelectorConnectionOpenConfirm)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().ConnectionOpenConfirm(0, cur, msg)
}

func ForceConnectionOpenConfirm(cur realm, msg types.MsgConnectionOpenConfirm) {
	access.AssertCanCall(0, cur, SelectorForceConnectionConfirm)
	mustValidate(msg.ValidateBasic())
	mustGetImpl().ForceConnectionOpenConfirm(0, cur, msg)
}

