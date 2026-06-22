package core

// upgrade.gno is the single admin-gated swap point for the IBC host logic. The
// proxy keeps the Store and identity stable across upgrades; only `impl` changes.
//
// Activation note: core's public entrypoints will delegate to `impl` once the
// logic and its tests are migrated to the impl realm. core's own package tests
// cannot import the impl realm (import cycle), so flipping the entrypoints is a
// coordinated step done per subsystem alongside moving its tests.
var impl ICore = nil

// UpdateImpl installs or re-points the implementation. It is admin-gated and
// injects the proxy-owned store into the target, so the store needs no public
// getter — the only way to obtain it is through this gated install.
func UpdateImpl(cur realm, target ICore) {
	requireAdmin(cur, "UpdateImpl")
	if target == nil {
		panic("core: impl cannot be nil")
	}

	impl = target
}

// Impl reports whether an implementation is installed (false until the first
// UpdateImpl). Exposed for deploy/bootstrap checks.
func Impl() bool {
	return impl != nil
}
