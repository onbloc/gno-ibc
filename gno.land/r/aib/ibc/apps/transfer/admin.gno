package transfer

import (
	"chain/runtime/unsafe"

	"gno.land/p/nt/ufmt/v0"
)

// admin is the account allowed to register the forward handler (see
// forward.gno). The handler receives custody of every forwarded voucher and
// holds the authority to resolve those packets' acks, so registration is
// trusted-gated — never permissionless. Mirrors r/aib/ibc/core's admin.
var admin address

func init() {
	// Set admin to the deployer's EOA. In production this is non-empty.
	// In the gno test framework the base store is pre-loaded with
	// OriginCaller="" so admin stays empty; SetAdmin then acts as bootstrap.
	admin = unsafe.OriginCaller()
}

// SetAdmin sets or transfers the admin role. If no admin is currently set
// (e.g. in tests where init saw an empty OriginCaller), the first caller
// becomes admin. Once set, only the current admin can change it.
func SetAdmin(cur realm, newAdmin address) {
	if admin != "" {
		ensureAdminCaller()
	}
	admin = newAdmin
}

// ensureAdminCaller panics if the EOA that signed the tx is not the admin.
// Admin authority is bound to the tx-signing EOA (unsafe.OriginCaller), which
// has no cur equivalent; same rationale and tx.origin trade-off as the admin
// in r/aib/ibc/core.
func ensureAdminCaller() {
	caller := unsafe.OriginCaller()
	if caller != admin {
		panic(ufmt.Sprintf("unauthorized: caller %s is not the admin", caller))
	}
}

var (
	// forwardHandler is the single registered adapter. forwardHandlerAddr is its
	// realm address, which doubles as the "forward here" trigger: an inbound
	// voucher recv whose Receiver equals it is minted to the handler and routed
	// onward instead of credited to Receiver. forwardHandlerPkgPath gates
	// CompleteForwardAck to that same realm. See forward.gno for the ForwardHandler
	// interface and the forward flow that reads these.
	forwardHandler        ForwardHandler
	forwardHandlerAddr    address
	forwardHandlerPkgPath string
)

// RegisterForwardHandler installs the onward-forward handler. Admin-gated: only
// the admin may set it. Without this gate anyone could register a handler that
// captures all forwarded funds and forges their acks.
//
// The caller realm's address becomes the forward trigger address, and its
// package path becomes the authorized caller for CompleteForwardAck.
func RegisterForwardHandler(cur realm, handler ForwardHandler) {
	ensureAdminCaller()
	if handler == nil {
		panic("transfer: forward handler must not be nil")
	}
	caller := cur.Previous()
	if caller.IsUser() {
		panic("transfer: forward handler must be a realm")
	}
	forwardHandler = handler
	forwardHandlerAddr = caller.Address()
	forwardHandlerPkgPath = caller.PkgPath()
}
