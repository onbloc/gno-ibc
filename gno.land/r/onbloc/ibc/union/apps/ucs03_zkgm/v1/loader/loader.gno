package loader

import (
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func init(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.GetInstance(cross(cur)), []string{
		"gno.land/r/onbloc/ibc/union/core",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/loader",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1",
	}))
	zkgm.RegisterCoreApp(cross(cur))
}
