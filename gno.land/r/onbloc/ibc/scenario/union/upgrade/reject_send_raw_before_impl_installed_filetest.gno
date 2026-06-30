// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// reject_send_raw_before_impl_installed_filetest covers the gnokey
// call-facing SendRaw entrypoint. Valid hex inputs reach the same fail-closed
// impl gate as Send.

import (
	z "gno.land/p/onbloc/ibc/union/zkgm"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	println("[SCENARIO] 1. On a fresh proxy (constructor registered, never installed), call SendRaw")
	println("[EXPECTED] SendRaw fails closed until UpdateImpl installs an impl")
	zkgm.SendRaw(cross(cur), 1, 99, "0000000000000000000000000000000000000000000000000000000000000000", z.INSTR_VERSION_0, z.OP_CALL, "")
}

// Output:
// [SCENARIO] 1. On a fresh proxy (constructor registered, never installed), call SendRaw
// [EXPECTED] SendRaw fails closed until UpdateImpl installs an impl

// Error:
// implementation not installed
