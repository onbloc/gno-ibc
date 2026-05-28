package echo

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

// Keep PkgPath in sync with gnomod.toml.
const PkgPath = "gno.land/r/gnoswap/ibc/examples/echo"

type echoReceiver struct {
	calls        int
	lastCalldata []byte
}

var receiver = &echoReceiver{}

func init(cur realm) {
	zkgm.RegisterReceiver(cross(cur), receiver)
}

func (r *echoReceiver) OnZkgm(cur realm, env z.CallEnv) error {
	r.calls++
	// Copy the caller realm's bytes into echo's own storage; storing the
	// foreign slice directly would persist a tainted reference.
	r.lastCalldata = append([]byte(nil), env.Calldata...)
	return nil
}

func (r *echoReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	return errors.New("echo: intent settlement not implemented")
}

// Query helpers return scalar/immutable values for safe cross-realm reads.
func Calls() int           { return receiver.calls }
func LastCalldata() string { return string(receiver.lastCalldata) }
