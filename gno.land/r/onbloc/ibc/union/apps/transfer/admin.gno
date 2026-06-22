package transfer

import "chain"

// SetHook registers h as the active recv hook. The hook's Address() is
// automatically authorized to call Send(). Admin-only. Pass nil to clear.
func SetHook(cur realm, h TransferHook) {
	requireCanCall(0, cur, SelectorSetHook)
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
