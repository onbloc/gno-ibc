package mock

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

type Mock struct {
	Calls    int
	Last     z.CallEnv
	ErrorMsg string
	PanicMsg string
}

var receiver = &Mock{}

func init() {
	zkgm.RegisterReceiver(cross, receiver)
}

func Reset(cur realm) {
	receiver.Calls = 0
	receiver.Last = z.CallEnv{}
	receiver.ErrorMsg = ""
	receiver.PanicMsg = ""
}

func SetError(cur realm, msg string) {
	receiver.ErrorMsg = msg
}

func SetPanic(cur realm, msg string) {
	receiver.PanicMsg = msg
}

func Calls() int {
	return receiver.Calls
}

// Note: Getters take `cur realm` because they read mutable package state across
// realms. omitting it causes Gno to panic at the cross-realm boundary.

func LastCaller(cur realm) string             { return receiver.Last.Caller }
func LastSourceChannel(cur realm) string      { return receiver.Last.SourceChannel }
func LastDestinationChannel(cur realm) string { return receiver.Last.DestinationChannel }
func LastSender(cur realm) string             { return string(receiver.Last.Sender) }
func LastCalldata(cur realm) string           { return string(receiver.Last.Calldata) }
func LastRelayer(cur realm) string            { return string(receiver.Last.Relayer) }
func LastRelayerMsg(cur realm) string         { return string(receiver.Last.RelayerMsg) }

func LastPathDec(cur realm) string {
	if receiver.Last.Path == nil {
		return ""
	}
	return receiver.Last.Path.Dec()
}

func (m *Mock) OnZkgm(cur realm, env z.CallEnv) error {
	m.Calls++
	m.Last = env
	if m.PanicMsg != "" {
		panic(m.PanicMsg)
	}
	if m.ErrorMsg != "" {
		return errors.New(m.ErrorMsg)
	}
	return nil
}

func (m *Mock) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	return errors.New("intent not implemented")
}
