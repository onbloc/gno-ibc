// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/impl_isolation
package impl_isolation

import (
	impl "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1"
	_ "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1/loader"
)

// GetInstance is the other path to a callable *ZkgmV1. The blank import runs
// the production loader's init, installing the impl and setting zkgm.ImplPath().
// After that, GetInstance only serves the loader realm. A foreign caller is
// rejected before it can obtain the singleton needed to call
// Recv/IntentRecv/Ack/Timeout/Send.
func main(cur realm) {
	_ = impl.GetInstance(cross(cur))
}

// Error:
// not allowed
