// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/security
package security

// reject_direct_app_recv_filetest is the EXCEPTION-path security scenario (S-8.1 /
// S-6.3). The zkgm App receiver (OnRecvPacket) is what mints/unlocks tokens, but it
// is only meant to run when core dispatches a proven packet. An external realm cannot
// use it to force a no-proof mint: the App type is owned by the zkgm realm, so the
// Gno Phase-3 allocation guard rejects even *constructing* `&zkgm.App{}` from a
// foreign realm (and the OnRecvPacket body additionally guards with
// assertIsCoreRealm). There is no other exported mint/unlock surface. The rejection
// is the terminating panic matched by // Error:.

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	attackerAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Install the zkgm impl")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.RegisterCoreApp(cross(cur))
	println("")

	println("[SCENARIO] 2. An external caller tries to construct the App to force a mint -> rejected")
	testing.SetRealm(testing.NewUserRealm(attackerAddr))
	app := &zkgm.App{}
	app.OnRecvPacket(cross(cur), types.Packet{}, attackerAddr, nil)
}

// Output:
// [SCENARIO] 1. Install the zkgm impl
//
// [SCENARIO] 2. An external caller tries to construct the App to force a mint -> rejected

// Error:
// cannot allocate gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm.App in realm gno.land/r/onbloc/ibc/scenario/union/security
