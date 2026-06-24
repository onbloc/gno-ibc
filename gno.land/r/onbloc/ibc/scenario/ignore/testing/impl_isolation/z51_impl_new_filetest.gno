// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/impl_isolation
package impl_isolation

import (
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

// New is the other path to a callable *ZkgmV1. Register installs the impl and
// sets zkgm.ImplPath() to the production impl realm. After that, New only
// serves that realm. A foreign caller is rejected before it can obtain an impl
// object needed to call Recv/IntentRecv/Ack/Timeout/Send.
func main(cur realm) {
	impl.Register(cross(cur))
	_ = impl.New(cross(cur))
}

// Error:
// not allowed
