package transfer

import (
	"gno.land/p/aib/ibc/types"
	"gno.land/r/aib/ibc/core"
)

// This file is the transfer app's *generic* forward extension point. The app
// stays free of any downstream protocol (ZKGM, etc.): it only knows the
// ForwardHandler abstraction defined here. A separate adapter realm implements it,
// imports the downstream protocol, and registers itself via
// RegisterForwardHandler. The dependency direction is adapter -> transfer,
// never the reverse (transfer imports nothing of the adapter or its protocol).

// Request carries the details of an inbound voucher recv that the app asks the
// handler to route onward. All fields are primitives or the base-token key, so
// the handler needs nothing else from the app.
type Request struct {
	// SourceClient / DestinationClient identify the inbound aib IBC packet's
	// clients; DestinationClient is the local client whose deferred ack the
	// handler must eventually resolve via CompleteForwardAck.
	SourceClient      string
	DestinationClient string
	// Sequence is the inbound packet sequence.
	Sequence uint64
	// Receiver is the inbound packet Receiver (equals the handler's own address;
	// that equality is what selects the forward path).
	Receiver string
	// Memo is the raw ICS20 memo, opaque to the app; the handler interprets it.
	Memo string
	// BaseTokenKey is the grc20reg key of the minted voucher — used by the
	// handler to resolve the token (to escrow it) and as the cross-chain base
	// token identifier.
	BaseTokenKey string
	// Amount is the voucher amount minted to the handler.
	Amount int64
}

// ForwardHandler is implemented by a downstream-specific adapter realm and
// registered with the transfer app via RegisterForwardHandler. The interface
// lives here (not in the adapter) so the app depends only on the abstraction it
// consumes, never on any concrete downstream protocol.
type ForwardHandler interface {
	// Prepare validates a forward request WITHOUT taking custody. A non-nil
	// error rejects the recv (error ack / refund) BEFORE any voucher is minted,
	// so a malformed request never strands funds. It must not move any tokens.
	Prepare(cur realm, req Request) error

	// Execute is invoked AFTER the app has minted req.Amount of the voucher to
	// the handler's own realm address. The handler escrows/forwards the tokens
	// and records whatever it needs to later resolve the parent packet's ack via
	// CompleteForwardAck. It MUST panic on any failure past this point so the
	// whole recv tx reverts (mint included) rather than acking over stranded
	// funds; permanent input errors belong in Prepare instead.
	Execute(cur realm, req Request)
}

// ForwardHandlerAddress returns the registered handler's address (the forward
// trigger address), or the zero address if none is registered.
func ForwardHandlerAddress() address {
	return forwardHandlerAddr
}

// isForwardReceiver reports whether an inbound recv Receiver targets the
// registered forward handler.
func isForwardReceiver(receiver string) bool {
	return forwardHandler != nil && address(receiver) == forwardHandlerAddr
}

// CompleteForwardAck resolves the deferred acknowledgement of a forwarded
// packet once its onward leg settles. Callable ONLY by the registered handler.
//
// On failure it burns the voucher that the onward protocol refunded to the
// handler, so the error ack that refunds the original AtomOne sender is not
// double-counted. The burn amount and holder come from state transfer recorded
// at recv time, not from the caller, so a compromised handler cannot burn
// arbitrary balances.
func CompleteForwardAck(cur realm, clientID string, sequence uint64, success bool) {
	if forwardHandlerPkgPath == "" || cur.Previous().PkgPath() != forwardHandlerPkgPath {
		panic("transfer: caller is not the registered forward handler")
	}

	pending, found := getPendingForward(clientID, sequence)
	if !found {
		panic("transfer: no pending forward for the given packet")
	}
	deletePendingForward(clientID, sequence)

	var resolved types.Acknowledgement
	if success {
		result := types.NewResultAppAcknowledgement([]byte{byte(1)})
		resolved = types.Acknowledgement{AppAcknowledgements: [][]byte{result.MarshalJSON()}}
	} else {
		inst := getVoucher(pending.VoucherDenom)
		if inst == nil {
			panic("transfer: forward failed but voucher not found for " + pending.VoucherDenom)
		}
		if err := inst.ledger.Burn(pending.HandlerAddr, pending.Amount); err != nil {
			panic("transfer: forward refund burn failed: " + err.Error())
		}
		resolved = types.Acknowledgement{AppAcknowledgements: [][]byte{types.UniversalErrorAcknowledgement()}}
	}

	core.WriteAcknowledgement(cross(cur), clientID, sequence, resolved)
}
