package zkgm

import "strings"

// upgrade.gno is the single admin-gated swap point for the zkgm app logic. The
// proxy keeps the Store, identity, and escrow funds stable across upgrades; only
// the installed impl changes.
//
// The swap is two-phase, mirroring core's host upgrade model: an impl realm
// registers its constructor under its own package path via RegisterImpl (from its
// init), and the admin later activates a registered path via UpdateImpl. The
// proxy injects its own Store into the constructor, so the store needs no public
// getter — the only way to obtain it is through this gated install.
var (
	proxyAddress     address = ""
	currentImplPath  string
	currentImpl      IApp
	implConstructors map[string]func(store IStore) IApp
)

func init(cur realm) {
	proxyAddress = cur.Address()
	currentImpl = nil
	currentImplPath = ""
	implConstructors = make(map[string]func(store IStore) IApp)
}

func ProxyAddress() address {
	return proxyAddress
}

// RegisterImpl records an impl constructor under the calling realm's package
// path. It is called from the impl realm's init, so the path is permanent once
// installed: re-registration is rejected. The caller must be a sub-realm of this
// proxy (its path must be prefixed by the proxy path), matching core's host
// registration rule.
func RegisterImpl(cur realm, constructor func(store IStore) IApp) {
	currentPath := cur.PkgPath()
	previousPath := cur.Previous().PkgPath()

	prefix := currentPath + "/"

	if !strings.HasPrefix(previousPath, prefix) {
		panic("zkgm: previous impl path is not a prefix of the current impl path")
	}

	if _, ok := implConstructors[previousPath]; ok {
		panic("zkgm: impl already registered")
	}

	implConstructors[previousPath] = constructor
}

// UpdateImpl installs or re-points the implementation following the bootstrap and
// steady-state tiers of the trust model. It is admin-gated and injects the
// proxy-owned store into the registered constructor for path.
func UpdateImpl(cur realm, path string) {
	assertIsAdmin(cur)

	constructor, ok := implConstructors[path]
	if !ok {
		panic("zkgm: impl constructor not found")
	}

	currentImplPath = path
	currentImpl = constructor(store)
}

// mustGetImpl returns the installed impl, panicking until the first UpdateImpl.
func mustGetImpl() IApp {
	if currentImpl == nil {
		panic("zkgm: implementation not installed")
	}

	return currentImpl
}
