// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	upgradeimpl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgradeimpl"
)

func main(cur realm) {
	oldImpl := zkgm.ProxyPkgPath() + "/testing/upgrade-old"
	newImpl := zkgm.ProxyPkgPath() + "/testing/upgrade-new"
	balanceKey := "upgrade-continuity/channel-balance"

	println("[SCENARIO] 1. bootstrap old implementation")
	stdtesting.SetRealm(stdtesting.NewCodeRealm(oldImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "before"), []string{
		oldImpl,
		newImpl,
	}))
	zkgm.SetChannelBalanceV2(cross(cur), balanceKey, u256.NewUint(40))
	println("[EXPECTED] impl_path_before", zkgm.ImplPath())
	println("[EXPECTED] render_before", zkgm.Render(""))

	println("")
	println("[SCENARIO] 2. upgrade through allowed implementation")
	stdtesting.SetRealm(stdtesting.NewCodeRealm(newImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "after"), []string{
		newImpl,
	}))
	println("[EXPECTED] impl_path_after", zkgm.ImplPath())
	println("[EXPECTED] render_after", zkgm.Render(""))
	println("[EXPECTED] channel_balance_after", zkgm.GetChannelBalanceV2(balanceKey).Dec())
	println("[EXPECTED] old_impl_allowed", zkgm.InAllowedImpls(oldImpl))
	println("[EXPECTED] new_impl_allowed", zkgm.InAllowedImpls(newImpl))
}

// Output:
// [SCENARIO] 1. bootstrap old implementation
// [EXPECTED] impl_path_before gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgrade-old
// [EXPECTED] render_before before
//
// [SCENARIO] 2. upgrade through allowed implementation
// [EXPECTED] impl_path_after gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/upgrade-new
// [EXPECTED] render_after after
// [EXPECTED] channel_balance_after 40
// [EXPECTED] old_impl_allowed false
// [EXPECTED] new_impl_allowed true
