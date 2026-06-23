package impl

import (
	"errors"
	"strings"
)

// makeError builds a fresh error from one or more message parts joined by ", ".
// Errors are constructed at the call site (never shared package-level values) so
// the resulting object is owned by the current realm; propagating a shared
// sentinel across a realm boundary would carry a foreign-owned object. The base
// message constant comes first and any value-carrying detail (denom, path, id)
// after, e.g. makeError(errVoucherNotFound, ibcDenom).
func makeError(msgs ...string) error {
	return errors.New(strings.Join(msgs, ", "))
}

// Error messages for the zkgm v1 impl, collected in one place so the wording
// stays consistent. They are string constants rather than package-level error
// values; build them with makeError at the call site (see above).
const (
	// opcode routing
	errUnsupportedOpcode = "zkgm/v1: unsupported opcode"

	// instruction decoding
	errUnsupportedTokenOrderVersion = "zkgm/v1: unsupported token order version"
	errUnsupportedCallVersion       = "zkgm/v1: unsupported call version"
	errUnsupportedBatchVersion      = "zkgm/v1: unsupported batch version"
	errUnsupportedForwardVersion    = "zkgm/v1: unsupported forward version"

	// token order
	errInvalidUnescrow                    = "zkgm/v1: invalid token order unescrow"
	errUnknownTokenOrderKind              = "zkgm/v1: unknown token order kind"
	errUnknownFillType                    = "zkgm/v1: unknown fill type"
	errUnsupportedTokenOrderKindForAck    = "zkgm/v1: unsupported token order kind for ack"
	errUnsupportedTokenOrderKindForRefund = "zkgm/v1: unsupported token order kind for refund"
	errSolveNotImplemented                = "zkgm/v1: solve token order not implemented"
	errInvalidTokenOrderDestChannel       = "zkgm/v1: invalid token order destination channel"

	// call
	errEurekaUnsupported     = "zkgm/v1: eureka mode not supported"
	errInvalidCallSender     = "zkgm/v1: invalid call sender"
	errReceiverNotRegistered = "zkgm/v1: receiver not registered"

	// forward
	errInvalidForwardInstruction = "zkgm/v1: invalid forward instruction"
	errForwardMissingPrevDest    = "zkgm/v1: forward missing previous destination channel"
	errForwardMissingNextSource  = "zkgm/v1: forward missing next source channel"
	errForwardPrevDestMismatch   = "zkgm/v1: forward previous-destination mismatch"
	errForwardZeroTimeout        = "zkgm/v1: forward timeout timestamp must be non-zero"

	// batch
	errInvalidBatchInstruction = "zkgm/v1: invalid batch instruction"
	errBatchAckCountMismatch   = "zkgm/v1: batch ack count mismatch"

	// voucher
	errAmountOverflow  = "zkgm/v1: amount overflows int64"
	errVoucherNotFound = "zkgm/v1: voucher not found"

	// rate limit
	errTokenBucketAbsent = "zkgm/v1: token bucket is absent"

	// coins / channel balance
	errCoinMismatch            = "zkgm/coins: sent coin mismatch"
	errChannelBalanceUnderflow = "zkgm/channel_balance: underflow"
)
