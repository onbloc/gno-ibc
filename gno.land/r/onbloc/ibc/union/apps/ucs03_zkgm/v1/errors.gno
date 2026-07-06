package impl

import (
	"errors"
	"strings"
)

// Error messages for the zkgm v1 impl, collected in one place so the wording
// stays consistent. They are string constants rather than package-level error

// values; build them with makeError at the call site (see above).
const (
	// opcode routing
	errUnsupportedOpcode = "unsupported opcode"

	// instruction decoding
	errUnsupportedTokenOrderVersion = "unsupported token order version"
	errUnsupportedCallVersion       = "unsupported call version"
	errUnsupportedBatchVersion      = "unsupported batch version"
	errUnsupportedForwardVersion    = "unsupported forward version"

	// token order
	errInvalidUnescrow                    = "invalid token order unescrow"
	errTokenOrderFeeUnderflow             = "token order fee underflow: quote amount exceeds base amount"
	errUnknownTokenOrderKind              = "unknown token order kind"
	errUnknownFillType                    = "unknown fill type"
	errUnsupportedTokenOrderKindForAck    = "unsupported token order kind for ack"
	errUnsupportedTokenOrderKindForRefund = "unsupported token order kind for refund"
	errSolveNotImplemented                = "solve token order not implemented"
	errInvalidTokenOrderDestChannel       = "invalid token order destination channel"

	// call
	errEurekaUnsupported     = "eureka mode not supported"
	errInvalidCallSender     = "invalid call sender"
	errReceiverNotRegistered = "receiver not registered"
	errIsOnlyMakerAck        = "is only maker ack"

	// forward
	errInvalidForwardInstruction = "invalid forward instruction"
	errForwardMissingPrevDest    = "forward missing previous destination channel"
	errForwardMissingNextSource  = "forward missing next source channel"
	errForwardPrevDestMismatch   = "forward previous-destination mismatch"
	errForwardZeroTimeout        = "forward timeout timestamp must be non-zero"

	// batch
	errInvalidBatchInstruction = "invalid batch instruction"
	errBatchAckCountMismatch   = "batch ack count mismatch"

	// voucher
	errAmountOverflow  = "amount overflows int64"
	errVoucherNotFound = "voucher not found"

	// rate limit
	errTokenBucketAbsent = "token bucket is absent"

	// coins / channel balance
	errCoinMismatch            = "zkgm/coins: sent coin mismatch"
	errChannelBalanceUnderflow = "zkgm/channel_balance: underflow"
	errChannelBalanceOverflow  = "zkgm/channel_balance: overflow"

	// errGRC20Unsupported is returned when a token order's base denom is a GRC20
	// token registered in grc20reg (other than zkgm's own ibc/ vouchers). zkgm only
	// escrows native coins (pushed via -send) and the vouchers it issues; escrowing
	// a foreign GRC20 would require an Approve/TransferFrom pull path that is not yet
	// implemented. Detected explicitly so it fails with a clear message instead of
	// being misclassified as native and surfacing errCoinMismatch.
	errGRC20Unsupported = "grc20 token escrow not yet supported"

	// ErrSpoofedRealm guards non-crossing (_ int, rlm realm, ...) entrypoints: the
	// passed rlm must be the current crossing frame, not a forged or stale token.
	errSpoofedRealm = "rlm does not match the current crossing frame"
)

func makeError(msgs ...string) error {
	return errors.New(strings.Join(msgs, ", "))
}
