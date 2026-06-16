package nonimpl

import (
	"gno.land/p/nt/testutils/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func ReleaseNativeDirect(cur realm) {
	zkgm.ReleaseNative(cross(cur), "ugnot", testutils.TestAddress("nonimpl-recipient"), 1)
}
