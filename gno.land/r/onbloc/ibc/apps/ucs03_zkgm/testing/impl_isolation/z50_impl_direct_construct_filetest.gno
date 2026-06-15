// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/impl_isolation
package impl_isolation

import (
	impl "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1"
)

// A foreign realm cannot bypass core by constructing impl.ZkgmV1 directly and
// calling its crossing state-change methods:
//
//	(&impl.ZkgmV1{}).Recv(cross(cur), craftedUnescrowPacket, caller, nil)
//
// Gno Phase 3 makes that structurally impossible: a realm cannot allocate a
// struct type owned by another realm. Allocation aborts before any
// Recv/IntentRecv/Ack/Timeout/Send method can run.
func main(cur realm) {
	_ = &impl.ZkgmV1{}
}

// Error:
// cannot allocate gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1.ZkgmV1 in realm gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/impl_isolation
