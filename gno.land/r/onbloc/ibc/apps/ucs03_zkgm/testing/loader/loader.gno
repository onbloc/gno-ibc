package loader

import (
	zkgm "gno.land/r/onbloc/ibc/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1"
)

func init(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.GetInstance(cross(cur)), []string{
		"gno.land/r/onbloc/ibc/core",
		"gno.land/r/onbloc/ibc/apps/ucs03_zkgm",
		"gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1/loader",
		"gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1",
		"gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e",
		"gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls",
	}))
	zkgm.RegisterCoreApp(cross(cur))
}
