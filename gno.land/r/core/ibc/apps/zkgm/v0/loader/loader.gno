package loader

import (
	core "gno.land/r/aib/ibc/core"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	impl "gno.land/r/gnoswap/ibc/apps/zkgm/v0/impl"
)

const PortID = "ucs03-zkgm-0"

func init() {
	zkgm.UpdateImpl(cross, zkgm.UpdateRequest{
		Impl: impl.GetInstance(),
	})
	core.RegisterApp(cross, PortID, zkgm.AsIBCApp())
}
