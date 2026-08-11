package ucs03_zkgm

import (
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/access"
	"gno.land/r/onbloc/ibc/union/core"
)

// RegisterCoreApp registers the proxy App with core under the proxy pkgpath.
// core rejects re-registration, so the App identity is permanent once installed.
func RegisterCoreApp(cur realm) {
	core.RegisterApp(cross(cur), &App{})
}

// RegisterReceiver records the calling realm as an OP_CALL receiver target,
// keyed by its package path. The impl looks it up via store.GetReceiver during
// call dispatch.
func RegisterReceiver(cur realm, receiver z.Zkgmable) {
	receiverPkgPath := cur.Previous().PkgPath()
	store.SetReceiver(0, cur, receiverPkgPath, receiver)
	emitZkgmReceiverRegisteredEvent(receiverPkgPath)
}

// RegisterTokenForwardHandler installs the ESCROW TokenOrderV2 forward handler.
// Admin-gated: the handler receives custody of every forwarded voucher and
// resolves those packets' acks, so it must never be permissionless.
func RegisterTokenForwardHandler(cur realm, handler z.TokenForwardHandler) {
	access.AssertCanCall(0, cur, SelectorRegisterTokenForwardHandler)

	if handler == nil {
		panic("ucs03_zkgm: forward handler must not be nil")
	}

	caller := cur.Previous()
	if caller.IsUser() {
		panic("ucs03_zkgm: forward handler must be a realm")
	}

	store.SetTokenForwardHandler(0, cur, handler, caller.Address(), caller.PkgPath())
}

// CompleteTokenForwardAck resolves the deferred ack of an ESCROW TokenOrderV2
// order (see z.TokenForwardHandler) once the receiving realm's onward leg settles.
func CompleteTokenForwardAck(cur realm, corrID string, success bool, innerAck []byte) {
	mustGetImpl().CompleteTokenForwardAck(0, cur, corrID, success, innerAck)
}
