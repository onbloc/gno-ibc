package core

import "strings"

// upgrade.gno is the single admin-gated swap point for the IBC host logic. The
// proxy keeps the Store and identity stable across upgrades; only `impl` changes.
//
// Activation note: core's public entrypoints will delegate to `impl` once the
// logic and its tests are migrated to the impl realm. core's own package tests
// cannot import the impl realm (import cycle), so flipping the entrypoints is a
// coordinated step done per subsystem alongside moving its tests.
var (
	currentImplPath  string
	currentImpl      ICore
	implConstructors map[string]func(store IStore) ICore
)

func init() {
	currentImpl = nil
	currentImplPath = ""
	implConstructors = make(map[string]func(store IStore) ICore)
}

func RegisterImpl(cur realm, constructor func(store IStore) ICore) {
	currentPath := cur.PkgPath()
	previousPath := cur.Previous().PkgPath()

	prefix := currentPath + "/"

	if !strings.HasPrefix(previousPath, prefix) {
		panic("core: previous impl path is not a prefix of the current impl path")
	}

	if _, ok := implConstructors[previousPath]; ok {
		panic("core: impl already registered")
	}

	implConstructors[previousPath] = constructor
}

// UpdateImpl installs or re-points the implementation. It is admin-gated and
// injects the proxy-owned store into the target, so the store needs no public
// getter — the only way to obtain it is through this gated install.
func UpdateImpl(cur realm, path string) {
	requireAdmin(cur, "UpdateImpl")

	constructor, ok := implConstructors[path]
	if !ok {
		panic("core: impl constructor not found")
	}

	currentImplPath = path
	currentImpl = constructor(store)
}

func mustGetImpl() ICore {
	if currentImpl == nil {
		panic("core: implementation not installed")
	}

	return currentImpl
}
