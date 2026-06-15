package transfer

import (
	"chain"

	core "gno.land/r/onbloc/ibc/core"
)

// SetHook registers h as the active recv hook. The hook's Address() is
// automatically authorized to call Send(). Admin-only. Pass nil to clear.
func SetHook(cur realm, h TransferHook) {
	mustBeAdmin(cur)
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

func mustBeAdmin(cur realm) {
	if cur.Previous().Address() != core.GetAdmin() {
		panic("transfer: admin only")
	}
}
