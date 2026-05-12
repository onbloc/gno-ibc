package loader

import (
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	impl "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl"
)

func init() {
	zkgm.UpdateImpl(cross, zkgm.UpdateRequest{
		Impl:         impl.GetInstance(),
		AllowedImpls: []string{"gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"},
	})
	core.RegisterApp(cross, []byte(zkgm.ProxyAddress()), zkgm.AsIBCApp())
}
