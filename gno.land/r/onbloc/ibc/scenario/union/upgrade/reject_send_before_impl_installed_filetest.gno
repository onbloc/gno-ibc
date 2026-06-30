// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// reject_send_before_impl_installed_filetest covers the state-changing
// Send entrypoint. Importing the impl registers its constructor, but until
// UpdateImpl installs it the proxy must fail closed.

import (
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	println("[SCENARIO] 1. On a fresh proxy (constructor registered, never installed), call Send")
	println("[EXPECTED] state-changing sends fail closed until UpdateImpl installs an impl")
	zkgm.Send(cross(cur), types.ChannelId(1), types.Timestamp(99), [32]byte{}, z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL})
}

// Output:
// [SCENARIO] 1. On a fresh proxy (constructor registered, never installed), call Send
// [EXPECTED] state-changing sends fail closed until UpdateImpl installs an impl

// Error:
// implementation not installed
