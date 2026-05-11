package mock

import (
	"chain/runtime"
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

type Receiver struct {
	Calls            int
	Last             z.CallEnv
	LastOriginCaller string
	CaptureOrigin    bool
	ErrorMsg         string
	PanicMsg         string
}

var receiver = &Receiver{}

func init() {
	zkgm.RegisterReceiver(cross, receiver)
}

// Exported funcs in this package take `cur realm` because they read or
// write mutable package state across realms; omitting it causes Gno to
// panic at the cross-realm boundary. Per-field accessors return scalars
// or strings to avoid exposing tainted []byte/*u256.Uint to callers (see
// AGENT.md "Cross-Realm Reads: Tainted Slices and Pointers").

// Reset clears all captured state on the singleton receiver.
func Reset(cur realm) {
	receiver.Calls = 0
	receiver.Last = z.CallEnv{}
	receiver.LastOriginCaller = ""
	receiver.CaptureOrigin = false
	receiver.ErrorMsg = ""
	receiver.PanicMsg = ""
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

// SetCaptureOrigin toggles capture of runtime.OriginCaller() inside OnZkgm.
func SetCaptureOrigin(cur realm, on bool) {
	receiver.CaptureOrigin = on
}

// LastOriginCaller returns the OriginCaller captured during the last OnZkgm
// (only populated when SetCaptureOrigin was true).
func LastOriginCaller(cur realm) string { return receiver.LastOriginCaller }

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
	if r.CaptureOrigin {
		r.LastOriginCaller = runtime.OriginCaller().String()
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
	return errors.New("intent not implemented")
}
