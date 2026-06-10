// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	upgradeimpl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	currentImpl := zkgm.ProxyPkgPath() + "/testing/current"
	candidate := zkgm.ProxyPkgPath() + "/testing/candidate"

	stdtesting.SetRealm(stdtesting.NewCodeRealm(currentImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "current"), []string{
		candidate,
	}))

	stdtesting.SetRealm(stdtesting.NewCodeRealm(candidate))
	// Intentionally pass a non-nil empty allowlist: this clears allowedImpls,
	// removing candidate's own upgrade authority before the next call.
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), nil, []string{}))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "removed"), nil))
}

// Error:
// permission denied for prev realm: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/candidate
