package core

import (
	"strings"

	"gno.land/r/onbloc/ibc/union/access"
)

// upgrade.gno is the single admin-gated swap point for the IBC host logic. The
// proxy keeps the Store and identity stable across upgrades; only `impl` changes.
//
// Activation note: core's public entrypoints delegate to the installed impl.
// The impl realm registers its constructor from init(), and UpdateImpl injects
// the proxy-owned Store before any delegated entrypoint can run.
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

// RegisterImpl installs an impl constructor under its defining package path.
// It is called from the impl realm's init() and is NOT access-gated; the
// security boundary is the prefix check below plus the admin-gated UpdateImpl
// that actually selects which registered constructor to activate.
//
// SAFE: this prefix check trusts that the chain reserves the
// gno.land/r/onbloc/ibc/union/core/* namespace. If the chain permitted
// permissionless realm deployment under that path, an attacker could squat a
// constructor (e.g. under core/v2) and social-engineer an admin into calling
// UpdateImpl with that path. The mitigation is namespace reservation at the
// deployment layer; consider adding an explicit impl-path allowlist here if the
// chain does not reserve the namespace.
func RegisterImpl(cur realm, constructor func(store IStore) ICore) {
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

// UpdateImpl installs or re-points the implementation. It is admin-gated and
// injects the proxy-owned store into the target, so the store needs no public
// getter — the only way to obtain it is through this gated install.
func UpdateImpl(cur realm, path string) {
	access.AssertCanCall(0, cur, SelectorUpdateImpl)

	constructor, ok := implConstructors[path]
	if !ok {
		panic("impl constructor not found")
	}

	currentImplPath = path
	currentImpl = constructor(store)
}

func mustGetImpl() ICore {
	if currentImpl == nil {
		panic("implementation not installed")
	}

	return currentImpl
}
