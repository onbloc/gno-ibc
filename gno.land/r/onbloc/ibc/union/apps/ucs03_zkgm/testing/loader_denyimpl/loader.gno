package loader_denyimpl

import (
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func init(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.New(cross(cur)), []string{
		"gno.land/r/onbloc/ibc/union/core",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls",
	}))
	zkgm.RegisterCoreApp(cross(cur))
}
