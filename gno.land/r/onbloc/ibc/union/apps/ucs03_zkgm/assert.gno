package zkgm

import core "gno.land/r/onbloc/ibc/union/core"

// assert.gno holds the proxy's trust gates. The App receiver surface is reachable
// only through core (assertIsIBCHost), while governance entrypoints use the app's
// access manager state. State writes are gated by the interrealm borrow rule on
// the injected store, so no separate impl-realm gate is needed here.

func assertIsIBCHost(cur realm) {
	if cur.Previous().PkgPath() != core.PackagePath() {
		panic("zkgm: ibc host only")
	}
}

func assertNotPaused() {
	if paused {
		panic("zkgm: paused")
	}
}
