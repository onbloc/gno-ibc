package zkgm

import u256 "gno.land/p/onbloc/math/uint256"

// Zkgmable is implemented by realms that receive ZKGM Call instructions
// dispatched from the ZKGM proxy.
type Zkgmable interface {
	// OnZkgm handles a standard ZKGM Call.
	OnZkgm(cur realm, env CallEnv) error

	// OnIntentZkgm handles the intent-settlement Call variant.
	OnIntentZkgm(cur realm, env IntentCallEnv) error
}

// SendCallback is implemented by realms that want to be notified of the
// ack/timeout outcome of a packet they sent via SendWithCallback. corrID is
// the exact string the caller passed to SendWithCallback, echoed back
// verbatim so the caller can resolve its own pending state without
// recomputing a packet hash itself.
type SendCallback interface {
	OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error
}

// TokenForwardRequest carries an inbound ESCROW TokenOrderV2 addressed to the
// registered forward handler. Metadata doubles as an opaque routing memo
// here, since ESCROW orders otherwise ignore that field.
type TokenForwardRequest struct {
	SourceChannel      string
	DestinationChannel string
	Receiver           string // handler's own registered address
	Memo               []byte // order's raw Metadata
	BaseTokenKey       string // grc20reg key of the minted voucher
	Amount             int64
}

// TokenForwardHandler is registered via RegisterTokenForwardHandler to
// receive ESCROW orders addressed to it, deferring the ack until resolved
// via CompleteTokenForwardAck. Mirrors transfer.ForwardHandler.
type TokenForwardHandler interface {
	// Prepare validates req without taking custody; a non-nil error rejects
	// the recv before any voucher is minted.
	Prepare(cur realm, req TokenForwardRequest, corrID string) error

	// Execute runs after the voucher is minted to the handler; it must panic
	// on failure so the whole recv tx reverts.
	Execute(cur realm, req TokenForwardRequest, corrID string)
}

type CallEnv struct {
	Caller             string
	ProxyAccount       string
	Path               *u256.Uint
	SourceChannel      string
	DestinationChannel string
	Sender             []byte
	Calldata           []byte
	Relayer            []byte
	RelayerMsg         []byte
}

type IntentCallEnv struct {
	Caller             string
	ProxyAccount       string
	Path               *u256.Uint
	SourceChannel      string
	DestinationChannel string
	Sender             []byte
	Calldata           []byte
	MarketMaker        []byte
	MarketMakerMsg     []byte
}
