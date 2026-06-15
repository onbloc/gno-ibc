// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/upgrade
package upgrade

import zkgm "gno.land/r/onbloc/ibc/apps/ucs03_zkgm"

func main(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), nil, []string{
		zkgm.ProxyPkgPath() + "/v0/impl",
	}))
}

// Error:
// zkgm: bootstrap UpdateImpl must install an impl
