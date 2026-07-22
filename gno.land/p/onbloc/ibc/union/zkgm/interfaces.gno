package zkgm

import u256 "gno.land/p/gnoswap/uint256"

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
