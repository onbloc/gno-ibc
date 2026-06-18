package zkgm

import (
	app "gno.land/p/onbloc/ibc/union/app"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

// proxyPkgPath is this proxy realm's package path — the stable IBC port id that
// core keys the App registration under.
const proxyPkgPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"

func ProxyPkgPath() string {
	return proxyPkgPath
}

// AsIBCApp returns the stable App reference core routes packets to.
func AsIBCApp() app.IApp {
	return &App{}
}

// RegisterCoreApp registers the proxy App with core under the proxy pkgpath.
// core rejects re-registration, so the App identity is permanent once installed.
func RegisterCoreApp(cur realm) {
	core.RegisterApp(cross(cur), AsIBCApp())
}

// RegisterReceiver records the calling realm as an OP_CALL receiver target,
// keyed by its package path. The impl looks it up via store.GetReceiver during
// call dispatch.
func RegisterReceiver(cur realm, receiver z.Zkgmable) {
	store.SetReceiver(0, cur, cur.Previous().PkgPath(), receiver)
}
