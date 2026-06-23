package zkgm

import "gno.land/r/onbloc/ibc/union/access"

// assert.gno holds the proxy's trust gates. The App receiver surface is reachable
// only through core (assertIsIBCHost), while governance entrypoints use the app's
// access manager state. State writes are gated by the interrealm borrow rule on
// the injected store, so no separate impl-realm gate is needed here.

func assertIsIBCHost(cur realm) {
	if cur.Previous().PkgPath() != access.CoreRealmPath {
		panic("zkgm: ibc host only")
	}
}

func assertIsNotPaused() {
	if paused {
		panic("zkgm: paused")
	}
}
