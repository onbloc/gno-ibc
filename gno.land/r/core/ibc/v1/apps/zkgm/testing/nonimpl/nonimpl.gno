package nonimpl

import (
	"gno.land/p/nt/testutils/v0"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
)

func ReleaseNativeDirect(cur realm) {
	zkgm.ReleaseNative(cross(cur), "ugnot", testutils.TestAddress("nonimpl-recipient"), 1)
}
