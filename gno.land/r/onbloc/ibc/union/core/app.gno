package core

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// RegisterApp registers an IBC application at the caller realm's package path,
// delegating to the installed mustGetImpl().
func RegisterApp(cur realm, app app.IApp) {
	mustGetImpl().RegisterApp(0, cur, app)
}

// RegisterAppForPort registers an IBC application at an explicit port id. This
// privileged path is for deployment/loaders that install an app on behalf of
// another realm.
func RegisterAppForPort(cur realm, portId []byte, app app.IApp) {
	access.AssertCanCall(cross(cur), SelectorRegisterPort, cur.Previous().Address())
	store.RegisterAppAtPort(0, cur, types.Bytes(portId), app)
	EmitAppRegistered(portId, cur.Previous().PkgPath(), true)
}

// HasApp reports whether an app is registered at portId.
func HasApp(portId []byte) bool {
	_, ok := store.ports[string(portId)]
	return ok
}
