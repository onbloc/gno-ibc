package ucs03_zkgm

import (
	"errors"

	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// mock_receiver_test.gno is a recording OP_CALL receiver used by the call and
// batch dispatch tests. The impl dispatches receivers through
// receiver.OnZkgm(cross(rlm), env), so the mock implements z.Zkgmable and
// records each invocation on a package-level singleton.
//
// A receiver defined inside this test package works across the cross(rlm)
// dispatch boundary, so the tests no longer need a separate receiver realm.
// Helper funcs take `cur realm` and return scalars/strings, mirroring the
// cross-realm read rules in AGENTS.md.

type mockReceiver struct {
	calls       int
	last        z.CallEnv
	intentCalls int
	lastIntent  z.IntentCallEnv
	errorMsg    string
	panicMsg    string
}

var mockRcvr = &mockReceiver{}

// Zkgmable exposes the singleton receiver as a z.Zkgmable for SetReceiver.
func Zkgmable(cur realm) z.Zkgmable {
	return mockRcvr
}

// Reset clears all captured state on the singleton receiver.
func Reset(cur realm) {
	mockRcvr.calls = 0
	mockRcvr.last = z.CallEnv{}
	mockRcvr.intentCalls = 0
	mockRcvr.lastIntent = z.IntentCallEnv{}
	mockRcvr.errorMsg = ""
	mockRcvr.panicMsg = ""
}

func Calls(cur realm) int       { return mockRcvr.calls }
func IntentCalls(cur realm) int { return mockRcvr.intentCalls }

func SetError(cur realm, msg string) { mockRcvr.errorMsg = msg }
func SetPanic(cur realm, msg string) { mockRcvr.panicMsg = msg }

func LastCalldata(cur realm) string           { return string(mockRcvr.last.Calldata) }
func LastCaller(cur realm) string             { return mockRcvr.last.Caller }
func LastProxyAccount(cur realm) string       { return mockRcvr.last.ProxyAccount }
func LastSourceChannel(cur realm) string      { return mockRcvr.last.SourceChannel }
func LastDestinationChannel(cur realm) string { return mockRcvr.last.DestinationChannel }
func LastSender(cur realm) string             { return string(mockRcvr.last.Sender) }
func LastRelayer(cur realm) string            { return string(mockRcvr.last.Relayer) }
func LastRelayerMsg(cur realm) string         { return string(mockRcvr.last.RelayerMsg) }

func LastPathDec(cur realm) string {
	if mockRcvr.last.Path == nil {
		return ""
	}

	return mockRcvr.last.Path.Dec()
}

func LastIntentCalldata(cur realm) string    { return string(mockRcvr.lastIntent.Calldata) }
func LastIntentMarketMaker(cur realm) string { return string(mockRcvr.lastIntent.MarketMaker) }

func (r *mockReceiver) OnZkgm(cur realm, env z.CallEnv) error {
	r.calls++
	r.last = env

	if r.panicMsg != "" {
		panic(r.panicMsg)
	}
	if r.errorMsg != "" {
		return errors.New(r.errorMsg)
	}

	return nil
}

func (r *mockReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	r.intentCalls++
	r.lastIntent = env

	if r.panicMsg != "" {
		panic(r.panicMsg)
	}
	if r.errorMsg != "" {
		return errors.New(r.errorMsg)
	}

	return nil
}
