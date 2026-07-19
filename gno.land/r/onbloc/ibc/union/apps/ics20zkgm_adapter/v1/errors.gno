package ics20zkgm_adapter

import (
	"errors"
	"strings"
)

// Error messages for the adapter's v1 impl, collected in one place so the
// wording stays consistent. Mirrors apps/ucs03_zkgm/v1/errors.gno: string
// constants rather than package-level error values, built with makeError at
// the call site.
const (
	// forward (OnTransferRecv)
	errReceiverNotAdapter = "ics20zkgm_adapter: forward requires ICS20 receiver to equal the adapter address"
	errDenomNotRegistered = "ics20zkgm_adapter: no forward config registered for denom"
	errInvalidAmount      = "ics20zkgm_adapter: invalid amount"
	errInvalidReceiver    = "ics20zkgm_adapter: invalid receiver"
	errEncodeTokenOrder   = "ics20zkgm_adapter: encode token order"

	// forward resolution (ResolveForward)
	errPendingForwardNotFound = "ics20zkgm_adapter: no pending forward for this packet hash"
	errForwardNotYetResolved  = "ics20zkgm_adapter: forward packet result not yet resolved"
	errWriteHookAckFailed     = "ics20zkgm_adapter: write hook ack failed"
)

func makeError(msgs ...string) error {
	return errors.New(strings.Join(msgs, ", "))
}
