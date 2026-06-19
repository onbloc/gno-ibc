package zkgm

import core "gno.land/r/onbloc/ibc/union/core"

// assert.gno holds the proxy's trust gates. The App receiver surface is reachable
// only through core (assertIsIBCHost); the governance surface only through the
// admin (assertIsAdmin); and both check assertNotPaused before delegating. State
// writes are gated by the interrealm borrow rule on the injected store, so no
// separate impl-realm gate is needed here.

func assertIsAdmin(cur realm) {
	if cur.Previous().Address() != core.GetAdmin() {
		panic("zkgm: admin only")
	}
}

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
