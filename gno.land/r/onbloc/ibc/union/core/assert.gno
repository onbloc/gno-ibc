package core

// assert.gno holds proxy-level trust gates shared across helper entrypoints.

func assertIsRlmCurrent(_ int, rlm realm) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}
}

func assertIsProxyRealm(_ int, rlm realm) {
	if rlm.PkgPath() != proxyPkgPath {
		panic(ErrNotProxyRealm)
	}
}
