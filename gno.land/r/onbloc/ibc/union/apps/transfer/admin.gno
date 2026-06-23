package transfer

import (
	"chain"

	"gno.land/p/onbloc/access/manager"
	"gno.land/r/onbloc/ibc/union/access"
)

const SelectorSetHook manager.Selector = "set_hook"

// SetHook registers h as the active recv hook. The hook's Address() is
// automatically authorized to call Send(). Admin-only. Pass nil to clear.
func SetHook(cur realm, h TransferHook) {
	access.AssertCanCall(cross(cur), SelectorSetHook, cur.Previous().Address())
	if h != nil && !h.Address().IsValid() {
		panic("transfer: hook address is invalid")
	}
	hook = h
	hookCaller = address("")
	if h != nil {
		hookCaller = h.Address()
	}
	chain.Emit(EventTypeHookSet,
		AttributeKeyHookCaller, hookCaller.String(),
	)
}
