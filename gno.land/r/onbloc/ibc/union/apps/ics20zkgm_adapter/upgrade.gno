package ics20zkgm_adapter

import (
	"strings"

	"gno.land/r/onbloc/ibc/union/access"
)

// upgrade.gno is the single admin-gated swap point for the adapter's business
// logic, mirroring apps/ucs03_zkgm/upgrade.gno: the proxy keeps a stable
// identity (used as transfer's hookCaller and the ZKGM receiver pkgpath)
// while the installed impl can be swapped. The swap is two-phase: an impl
// realm registers its constructor under its own package path via RegisterImpl
// (from its init), and the admin later activates a registered path via
// UpdateImpl.
var (
	// store is the proxy-owned singleton holding all persistent domain state
	// (the denom registry; see store.gno). It is injected into whichever impl
	// is active, so state survives impl upgrades.
	store            *Store
	proxyPkgPath     string
	proxyAddress     address
	currentImplPath  string
	currentImpl      IImpl
	implConstructors map[string]func(store IStore) IImpl
)

func init(cur realm) {
	store = NewStore()
	proxyPkgPath = cur.PkgPath()
	proxyAddress = cur.Address()
	implConstructors = make(map[string]func(store IStore) IImpl)
}

func ProxyPkgPath() string {
	return proxyPkgPath
}

func ProxyAddress() address {
	return proxyAddress
}

// RegisterImpl records an impl constructor under the calling realm's package
// path. It is called from the impl realm's init, so the path is permanent
// once installed: re-registration is rejected. The caller must be a
// sub-realm of this proxy (its path must be prefixed by the proxy path).
func RegisterImpl(cur realm, constructor func(store IStore) IImpl) {
	currentPath := cur.PkgPath()
	previousPath := cur.Previous().PkgPath()

	prefix := currentPath + "/"

	if !strings.HasPrefix(previousPath, prefix) {
		panic("previous impl path is not a prefix of the current impl path")
	}

	if _, ok := implConstructors[previousPath]; ok {
		panic("impl already registered")
	}

	implConstructors[previousPath] = constructor
}

// UpdateImpl installs or re-points the implementation. Admin-gated.
func UpdateImpl(cur realm, path string) {
	access.AssertCanCall(0, cur, SelectorUpdateImpl)

	constructor, ok := implConstructors[path]
	if !ok {
		panic("impl constructor not found")
	}

	oldImplPath := currentImplPath
	currentImplPath = path
	currentImpl = constructor(store)
	emitAdapterImplUpdatedEvent(cur.Previous().PkgPath(), oldImplPath, path)
}

// mustGetImpl returns the installed impl, panicking until the first UpdateImpl.
func mustGetImpl() IImpl {
	if currentImpl == nil {
		panic("implementation not installed")
	}

	return currentImpl
}
