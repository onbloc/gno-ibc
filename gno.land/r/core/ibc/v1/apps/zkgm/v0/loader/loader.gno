package loader

import (
	zkgm "gno.land/r/onbloc/ibc/v1/apps/zkgm"
	impl "gno.land/r/onbloc/ibc/v1/apps/zkgm/v0/impl"
)

func init(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.GetInstance(cross(cur)), []string{
		"gno.land/r/core/ibc/v1/core",
		"gno.land/r/onbloc/ibc/v1/apps/zkgm",
		"gno.land/r/onbloc/ibc/v1/apps/zkgm/v0/loader",
		"gno.land/r/onbloc/ibc/v1/apps/zkgm/v0/impl",
	}))
	zkgm.RegisterCoreApp(cross(cur))
}
