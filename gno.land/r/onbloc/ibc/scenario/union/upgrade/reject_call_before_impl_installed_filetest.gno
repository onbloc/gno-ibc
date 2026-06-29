// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// reject_call_before_impl_installed_filetest is the BOOTSTRAP-branch upgrade scenario
// (S-3.3, "impl 미설치 거부"). The zkgm proxy holds the persistent store and admin
// gates, but all behaviour is delegated to an installed implementation. Importing the
// v1 impl only registers its constructor (via the impl's init → RegisterImpl); it does
// NOT install it. Until the admin calls UpdateImpl, the proxy has no current impl, so
// every impl-delegating entrypoint must fail closed rather than silently no-op. This
// file calls an impl-backed getter on a fresh proxy (no UpdateImpl yet) and verifies it
// aborts with "implementation not installed". The terminating panic is the assertion.

import (
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1" // registers the constructor; does NOT install it
)

func main() {
	println("[SCENARIO] 1. On a fresh proxy (constructor registered, never installed), call an impl-backed getter")
	println("[EXPECTED] the proxy fails closed: no impl is installed until UpdateImpl")
	_, _ = zkgm.GetTokenBucket("ugnot")
}

// Output:
// [SCENARIO] 1. On a fresh proxy (constructor registered, never installed), call an impl-backed getter
// [EXPECTED] the proxy fails closed: no impl is installed until UpdateImpl

// Error:
// implementation not installed
