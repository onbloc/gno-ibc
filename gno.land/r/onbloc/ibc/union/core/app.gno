package core

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/r/onbloc/ibc/union/access"
)

// RegisterApp registers an IBC application at the caller realm's package path.
func RegisterApp(cur realm, app app.IApp) {
	caller := cur.Previous().PkgPath()
	portId := []byte(caller)
	registerAppAtPort(portId, app)
	emitAppRegisteredEvent(portId, caller, false)
}

// RegisterAppForPort registers an IBC application at an explicit port id. This
// privileged path is for deployment/loaders that install an app on behalf of
// another realm.
func RegisterAppForPort(cur realm, portId []byte, app app.IApp) {
	access.AssertCanCall(cross(cur), SelectorRegisterPort, cur.Previous().Address())
	registerAppAtPort(portId, app)
	emitAppRegisteredEvent(portId, cur.Previous().PkgPath(), true)
}

func registerAppAtPort(portId []byte, app app.IApp) {
	key := string(portId)
	if _, ok := store.ports[key]; ok {
		panic(ErrPortAlreadyRegistered)
	}
	store.ports[key] = app
}

// HasApp reports whether an app is registered at portId.
func HasApp(portId []byte) bool {
	_, ok := store.ports[string(portId)]
	return ok
}
