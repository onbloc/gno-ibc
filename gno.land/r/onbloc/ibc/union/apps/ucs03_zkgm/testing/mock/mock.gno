package mock

import (
	"errors"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

type Receiver struct {
	Calls              int
	Last               z.CallEnv
	IntentCalls        int
	LastIntent         z.IntentCallEnv
	LastPreviousCaller string
	CapturePrevious    bool
	ErrorMsg           string
	PanicMsg           string
}

var receiver = &Receiver{}

func init(cur realm) {
	zkgm.RegisterReceiver(cross(cur), receiver)
}

// Zkgmable exposes the singleton receiver as a z.Zkgmable so unit tests that
// inject a mock store can register it directly, rather than relying on the
// proxy's real receiver registry populated by init.
func Zkgmable(cur realm) z.Zkgmable {
	return receiver
}

// Exported funcs in this package take `cur realm` because they read or
// write mutable package state across realms; omitting it causes Gno to
// panic at the cross(cur)-realm boundary. Per-field accessors return scalars
// or strings to avoid exposing tainted []byte/*u256.Uint to callers (see
// AGENT.md "Cross-Realm Reads: Tainted Slices and Pointers").

// Reset clears all captured state on the singleton receiver.
func Reset(cur realm) {
	receiver.Calls = 0
	receiver.Last = z.CallEnv{}
	receiver.IntentCalls = 0
	receiver.LastIntent = z.IntentCallEnv{}
	receiver.LastPreviousCaller = ""
	receiver.CapturePrevious = false
	receiver.ErrorMsg = ""
	receiver.PanicMsg = ""
}

// IntentCalls returns the number of OnIntentZkgm invocations since the last Reset.
func IntentCalls(cur realm) int {
	return receiver.IntentCalls
}

// LastIntentCalldata returns env.Calldata from the last OnIntentZkgm invocation.
func LastIntentCalldata(cur realm) string {
	return string(receiver.LastIntent.Calldata)
}

// LastIntentMarketMaker returns env.MarketMaker (as a string) from the last OnIntentZkgm.
func LastIntentMarketMaker(cur realm) string {
	return string(receiver.LastIntent.MarketMaker)
}

// SetError configures OnZkgm to return an error with the given message.
func SetError(cur realm, msg string) {
	receiver.ErrorMsg = msg
}

// SetPanic configures OnZkgm to panic with the given message.
func SetPanic(cur realm, msg string) {
	receiver.PanicMsg = msg
}

// Calls returns the number of OnZkgm invocations since the last Reset.
func Calls(cur realm) int {
	return receiver.Calls
}

// SetCapturePrevious enables or disables capture of cur.Previous().Address()
// during OnZkgm. When enabled, the captured value can be retrieved via
// LastPreviousCaller.
func SetCapturePrevious(cur realm, on bool) {
	receiver.CapturePrevious = on
}

// LastPreviousCaller returns the previous caller address captured during the
// most recent OnZkgm. Empty unless SetCapturePrevious(true) was enabled.
func LastPreviousCaller(cur realm) string { return receiver.LastPreviousCaller }

// LastCaller returns env.Caller from the last OnZkgm invocation.
func LastCaller(cur realm) string { return receiver.Last.Caller }

// LastProxyAccount returns env.ProxyAccount from the last OnZkgm invocation.
func LastProxyAccount(cur realm) string { return receiver.Last.ProxyAccount }

// LastSourceChannel returns env.SourceChannel from the last OnZkgm invocation.
func LastSourceChannel(cur realm) string { return receiver.Last.SourceChannel }

// LastDestinationChannel returns env.DestinationChannel from the last OnZkgm.
func LastDestinationChannel(cur realm) string { return receiver.Last.DestinationChannel }

// LastSender returns env.Sender (decoded as a string) from the last OnZkgm.
func LastSender(cur realm) string { return string(receiver.Last.Sender) }

// LastCalldata returns env.Calldata (decoded as a string) from the last OnZkgm.
func LastCalldata(cur realm) string { return string(receiver.Last.Calldata) }

// LastRelayer returns env.Relayer (decoded as a string) from the last OnZkgm.
func LastRelayer(cur realm) string { return string(receiver.Last.Relayer) }

// LastRelayerMsg returns env.RelayerMsg (decoded as a string) from the last OnZkgm.
func LastRelayerMsg(cur realm) string { return string(receiver.Last.RelayerMsg) }

// LastPathDec returns env.Path.Dec() from the last OnZkgm, or "" if Path was nil.
func LastPathDec(cur realm) string {
	if receiver.Last.Path == nil {
		return ""
	}
	return receiver.Last.Path.Dec()
}

func (r *Receiver) OnZkgm(cur realm, env z.CallEnv) error {
	r.Calls++
	r.Last = env
	if r.CapturePrevious {
		r.LastPreviousCaller = cur.Previous().Address().String()
	}
	if r.PanicMsg != "" {
		panic(r.PanicMsg)
	}
	if r.ErrorMsg != "" {
		return errors.New(r.ErrorMsg)
	}
	return nil
}

func (r *Receiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	r.IntentCalls++
	r.LastIntent = env
	if r.CapturePrevious {
		r.LastPreviousCaller = cur.Previous().Address().String()
	}
	if r.PanicMsg != "" {
		panic(r.PanicMsg)
	}
	if r.ErrorMsg != "" {
		return errors.New(r.ErrorMsg)
	}
	return nil
}
