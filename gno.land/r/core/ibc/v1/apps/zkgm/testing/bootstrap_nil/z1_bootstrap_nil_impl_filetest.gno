// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/bootstrap_nil
package bootstrap_nil

import zkgm "gno.land/r/onbloc/ibc/v1/apps/zkgm"

func main(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), nil, []string{
		zkgm.ProxyPkgPath() + "/v0/impl",
	}))
}

// Error:
// zkgm: bootstrap UpdateImpl must install an impl
