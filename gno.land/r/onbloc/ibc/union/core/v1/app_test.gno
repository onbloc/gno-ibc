package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

const (
	coreRealmPath = "gno.land/r/onbloc/ibc/union/core"
)

func TestRegisterApp(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()

	v.RegisterApp(0, cur, &mockApp{})

	// The app is registered under the caller's package path.
	uassert.True(t, v.store.HasApp(types.Bytes(cur.Previous().PkgPath())))
}

func TestRegisterAppRejectsDuplicatePort(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	// The duplicate guard lives in the store (RegisterApp derives the caller's
	// port and delegates). Drive it with an explicit port id, since uassert's
	// closure crosses and would otherwise change the derived caller port.
	v := newTestImpl()
	ms := v.store.(*mockStore)
	portId := types.Bytes("dup-port")
	ms.RegisterAppAtPort(0, cur, portId, &mockApp{})

	uassert.AbortsContains(t, cur, "already registered", func(cur realm) {
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		ms.RegisterAppAtPort(0, cur, portId, &mockApp{})
	})
}
